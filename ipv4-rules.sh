#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function addCommon() {
  iptables -P INPUT ${DEFAULT_POLICY_INPUT:-$jump}
  iptables -P OUTPUT ACCEPT

  # allow loopback
  iptables -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j $jump
  iptables -A INPUT -m conntrack --ctstate INVALID -j $jump

  # do not touch established connections
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.+\..+\..+\..+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"0.0.0.0/0"}; do
    iptables -A INPUT -p tcp --dst $i --dport ${port:-22} --syn -j ACCEPT
  done

  # ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request -j $jump
}

function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name hash:ip family inet ${2-}"

  if ! $cmd 2>/dev/null; then
    if ! (saveIpset $name && ipset destroy $name && $cmd); then
      return 1
    fi
  fi
}

function __fill_trustlist() {
  (
    echo 193.187.88.42 193.187.88.43 193.187.88.44 193.187.88.45 193.187.88.46 141.212.118.18
    echo 45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.39 131.188.40.189 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118
    getent ahostsv4 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -u
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a[0]' <<<$relays |
          grep -F '.'
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function __fill_multilists() {
  sleep 2
  if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o -); then
    if [[ $relays =~ 'relays_published' ]]; then
      set -o pipefail
      if sorted=$(jq -r '.relays[] | select(.r == true) | .a[0]' <<<$relays |
        grep -F '.' |
        sort | uniq -c); then
        for i in 2 4 8; do
          awk '$1 > '$i'/2 && $1 <= '$i' { print $2 }' <<<$sorted >/var/tmp/$multilist-$i
        done
        awk '{ print $2 }' <<<$sorted >/var/tmp/relays.new
        mv /var/tmp/relays.new /var/tmp/relays
      fi
      set +o pipefail
    fi
  fi

  for i in 2 4 8; do
    if [[ -s /var/tmp/$multilist-$i ]]; then
      ipset flush $multilist-$i
      xargs -r -n 1 -P $jobs ipset add -exist $multilist-$i </var/tmp/$multilist-$i
    fi
  done
}

function __fill_ddoslist() {
  if [[ -s /var/tmp/$ddoslist ]]; then
    xargs -r -L 1 -P $jobs ipset add -exist $ddoslist </var/tmp/$ddoslist
  fi
  rm /var/tmp/$ddoslist
}

function addTor() {
  __create_ipset $trustlist "maxelem 64"
  __fill_trustlist &
  for i in 2 4 8; do
    __create_ipset $multilist-$i "maxelem 8192"
  done
  __fill_multilists &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask $prefix"
  for relay in $*; do
    if [[ $relay =~ '[' || $relay =~ ']' || ! $relay =~ '.' || ! $relay =~ ':' ]]; then
      echo " relay '$relay' cannot be parsed" >&2
      return 1
    fi
    read -r orip orport <<<$(tr ':' ' ' <<<$relay)
    local synpacket="iptables -A INPUT -p tcp --dst $orip --dport $orport --syn"

    local ddoslist="tor-ddos-$orport" # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "maxelem $max timeout $((24 * 3600))"
    __fill_ddoslist &

    # rule 1
    $synpacket -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    for i in 2 4 8; do
      $synpacket -m set --match-set $multilist-$i src -m set ! --match-set $ddoslist src -m connlimit --connlimit-mask $prefix --connlimit-upto $i -j ACCEPT
    done

    # rule 3
    $synpacket $hashlimit --hashlimit-name tor-ddos-$orport --hashlimit-above 6/minute --hashlimit-burst 5 --hashlimit-htable-expire $((2 * 60 * 1000)) -j SET --add-set $ddoslist src --exist
    $synpacket -m set --match-set $ddoslist src -j $jump

    # rule 4
    $synpacket -m connlimit --connlimit-mask $prefix --connlimit-above 2 -j $jump

    # rule 5
    $synpacket $hashlimit --hashlimit-name tor-rate-$orport --hashlimit-above 1/hour --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j $jump

    # rule 6
    $synpacket -j ACCEPT
  done
}

function addLocalServices() {
  local addr
  local port

  for service in ${ADD_LOCAL_SERVICES-}; do
    read -r addr port <<<$(tr ':' ' ' <<<$service)
    if [[ $addr == "0.0.0.0" ]]; then
      addr+="/0"
    fi
    iptables -A INPUT -p tcp --dst $addr --dport $port --syn -j ACCEPT
  done
}

function addHetzner() {
  local sysmon="hetzner-sysmon"

  __create_ipset $sysmon
  {
    (
      echo 188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86
      getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
    ) |
      xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
  iptables -A INPUT -m set --match-set $sysmon src -j ACCEPT
}

function setSysctlValues() {
  sysctl -q -w net.ipv4.tcp_syncookies=1
  # make tcp_max_syn_backlog big enough to have ListenDrops being low or 0:
  # awk '(f==0) {i=1; while (i<=NF) {n[i] = $i; i++ }; f=1; next} (f==1){i=2; while (i<=NF) {printf "%s = %d\n", n[i], $i; i++}; f=0}' /proc/net/netstat | grep 'Drop'
  for i in net.netfilter.nf_conntrack_buckets net.ipv4.tcp_max_syn_backlog net.core.somaxconn; do
    if [[ $(sysctl -n $i) -lt $max ]]; then
      sysctl -q -w $i=$max
    fi
  done
  local current=$(sysctl -n net.netfilter.nf_conntrack_max)
  if [[ $current -lt $max ]]; then
    sysctl -q -w net.netfilter.nf_conntrack_max=$((current + max))
  fi
}

function clearRules() {
  iptables -P INPUT ACCEPT
  iptables -P OUTPUT ACCEPT

  iptables -F
  iptables -X
  iptables -Z
}

function printRuleStatistics() {
  date -R
  echo
  iptables -nv -L INPUT
}

function getConfiguredRelays() {
  # shellcheck disable=SC2045
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null); do
    if orport=$(grep "^ORPort *" $f | grep -v -F -e ' NoListen' -e '[' | grep -P "^ORPort\s+.+\s*"); then
      if grep -q -Po "^ORPort\s+\d+\.\d+\.\d+\.\d+\:\d+\s*" <<<$orport; then
        awk '{ print $2 }' <<<$orport
      else
        if address=$(grep -P "^Address\s+\d+\.\d+\.\d+\.\d+\s*" $f); then
          echo $(awk '{ print $2 }' <<<$address):$(awk '{ print $2 }' <<<$orport)
        fi
      fi
    fi
  done
}

function bailOut() {
  local rc=$?

  local signal=$((rc - 128))
  if [[ $signal -eq 13 ]]; then # PIPE
    return
  fi
  trap - INT QUIT TERM EXIT

  echo -e "\n Something went wrong, stopping ...\n" >&2
  clearRules
  exit $rc
}

function saveIpset() {
  local name=$1
  local suffix=${2-}

  rm -f /var/tmp/$name.new
  ipset list $name | sed -e '1,8d' >/var/tmp/$name.new
  if [[ -s /var/tmp/$name.new ]]; then
    mv /var/tmp/$name.new /var/tmp/${name}${suffix}
  fi
}

function saveCertainIpsets() {
  local suffix=${1-}

  ipset list -t | grep '^Name: ' | grep -e 'tor-ddos-' -e 'tor-multi$' | awk '{ print $2 }' |
    while read -r name; do
      saveIpset $name $suffix
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

trustlist="tor-trust"      # Tor authorities and snowflake servers
multilist="tor-multi"      # Tor relay ip addresses hosting > 1 relay
jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding ips to an ipset
prefix=32                  # any ipv4 address of this /block is considered to belong to the same source/owner
# hash and ipset size
if [[ $(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo) -gt 2 ]]; then
  max=$((2 ** 18)) # RAM is bigger than 2 GiB
else
  max=$((2 ** 16)) # default: 65536
fi

jump=${RUN_ME_WITH_SAFE_JUMP_TARGET:-DROP}
action=${1-}
[[ $# -gt 0 ]] && shift
case $action in
start)
  trap bailOut INT QUIT TERM EXIT
  clearRules
  setSysctlValues
  addCommon
  addHetzner
  addLocalServices
  addTor ${*:-${CONFIGURED_RELAYS:-$(getConfiguredRelays)}}
  trap - INT QUIT TERM EXIT
  ;;
stop)
  saveCertainIpsets
  clearRules
  ;;
update)
  __fill_trustlist
  __fill_multilists
  ;;
test)
  export RUN_ME_WITH_SAFE_JUMP_TARGET="ACCEPT"
  $0 start $*
  ;;
save)
  saveCertainIpsets ${1-}
  ;;
*)
  printRuleStatistics
  ;;
esac
