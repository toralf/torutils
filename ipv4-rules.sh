#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# addCommon() and addTor() implement a DDoS solution for a Tor relay for IPv4
# the remaining code just parses the config and maintains ipset content
# https://github.com/toralf/torutils

function relay_2_ip_and_port() {
  if [[ $relay =~ '[' || $relay =~ ']' || ! $relay =~ '.' || ! $relay =~ ':' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(tr ':' ' ' <<<$relay)
}

function addCommon() {
  # allow loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "DDoS IPv4 $(date -R)" -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  $ipt -A INPUT -p tcp ! --syn -m state --state NEW -j $jump
  $ipt -A INPUT -m conntrack --ctstate INVALID -j $jump

  # do not touch established connections
  $ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.+\..+\..+\..+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"0.0.0.0/0"}; do
    $ipt -A INPUT -p tcp --dst $i --dport ${port:-22} --syn -j ACCEPT
  done

  # ratelimit ICMP echo
  $ipt -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT

  # DHCPv4
  $ipt -A INPUT -p udp --dport 68 -j ACCEPT
}

function addTor() {
  __create_ipset $trustlist "maxelem $((2 ** 6))"
  __fill_trustlist &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask $prefix"
  for relay in $*; do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    local ddoslist="tor-ddos-$orport" # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "maxelem $max timeout $((24 * 3600))"
    __fill_ddoslist &

    # rule 1
    local trust_rule="INPUT -p tcp --dst $orip --syn -m set --match-set $trustlist src -j ACCEPT"
    if ! $ipt -C $trust_rule 2>/dev/null; then
      $ipt -A $trust_rule
    fi

    # rule 2
    $common $hashlimit --hashlimit-name tor-ddos-$orport --hashlimit-above 9/minute --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j SET --add-set $ddoslist src --exist
    $common -m set --match-set $ddoslist src -j $jump

    # rule 3
    $common -m connlimit --connlimit-mask $prefix --connlimit-above 9 -j $jump

    # rule 4
    $common --syn -j ACCEPT
  done
}

function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name hash:ip family inet ${2-}"

  if ! $cmd 2>/dev/null; then
    if ! saveIpset $name && ipset destroy $name && $cmd; then
      return 1
    fi
  fi
}

function __fill_trustlist() {
  # this is intentionally not filled from a saved set at reboot
  (
    # snowflakes
    echo 193.187.88.42 193.187.88.43 193.187.88.44 193.187.88.45 193.187.88.46 141.212.118.18
    # Tor authorities
    echo 45.66.35.11 66.111.2.131 128.31.0.39 131.188.40.189 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118 216.218.219.41 217.196.147.77
    getent ahostsv4 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -u
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a[0]' <<<$relays |
          sort
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function __fill_ddoslist() {
  if [[ -s $tmpdir/$ddoslist ]]; then
    ipset flush $ddoslist
    xargs -r -L 1 -P $jobs ipset add -exist $ddoslist <$tmpdir/$ddoslist # -L 1 b/c the inputs are tuples
  fi
  rm -f $tmpdir/$ddoslist
}

function additionalServices() {
  # local-address:local-port
  for service in ${ADD_LOCAL_SERVICES-}; do
    read -r addr port <<<$(tr ':' ' ' <<<$service)
    if [[ $addr == "0.0.0.0" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --dst $addr --dport $port --syn -j ACCEPT
  done

  # remote-address>local-port
  for service in ${ADD_REMOTE_SERVICES-}; do
    read -r addr port <<<$(tr '>' ' ' <<<$service)
    if [[ $addr == "0.0.0.0" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --src $addr --dport $port --syn -j ACCEPT
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
  $ipt -A INPUT -m set --match-set $sysmon src -j ACCEPT
}

function setSysctlValues() {
  if modinfo nf_conntrack &>/dev/null && ! lsmod | grep -q 'nf_conntrack'; then
    modprobe nf_conntrack
  fi

  sysctl -q -w net.netfilter.nf_conntrack_max=$((2 ** 21)) || sysctl -q -w net.nf_conntrack_max=$((2 ** 21))
  sysctl -q -w net.ipv4.tcp_syncookies=1

  # make tcp_max_syn_backlog big enough to have ListenDrops being low or 0:
  # awk '(f==0) {i=1; while (i<=NF) {n[i] = $i; i++ }; f=1; next} (f==1){i=2; while (i<=NF) {printf "%s = %d\n", n[i], $i; i++}; f=0}' /proc/net/netstat | grep 'Drop'
  for i in net.netfilter.nf_conntrack_buckets net.ipv4.tcp_max_syn_backlog net.core.somaxconn; do
    if [[ $(sysctl -n $i) -lt $max ]]; then
      sysctl -q -w $i=$max
    fi
  done
}

function clearRules() {
  $ipt -P INPUT ACCEPT

  $ipt -F
  $ipt -X
  $ipt -Z
}

function printRuleStatistics() {
  date -R
  echo
  $ipt -nv -L INPUT $*
}

# OR port and address are defined in 1 or 2 lines
function getConfiguredRelays() {
  # shellcheck disable=SC2045
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null); do
    if orport=$(grep "^ORPort *" $f | grep -v -F -e ' NoListen' -e '[' -e ':auto' | grep -P "^ORPort\s+.+\s*"); then
      if grep -q -Po "^ORPort\s+\d+\.\d+\.\d+\.\d+\:\d+\s*" <<<$orport; then
        awk '{ print $2 }' <<<$orport
      elif address=$(grep -P "^Address\s+\d+\.\d+\.\d+\.\d+\s*" $f); then
        echo $(awk '{ print $2 }' <<<$address):$(awk '{ print $2 }' <<<$orport)
      fi
    fi
  done
}

function bailOut() {
  local rc=$?

  if [[ $rc -gt 128 ]]; then
    local signal=$((rc - 128))
    if [[ $signal -eq 13 ]]; then # PIPE
      return 0
    fi
  fi

  trap - INT QUIT TERM EXIT
  echo -e "\n Something went wrong, stopping ...\n" >&2
  clearRules
  exit $rc
}

function saveIpset() {
  local name=$1

  local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
  if ipset list $name | sed -e '1,8d' >$tmpfile; then
    if [[ -s $tmpfile ]]; then
      cp $tmpfile $tmpdir/$name
    fi
  fi
  rm $tmpfile
}

function saveCertainIpsets() {
  ipset list -n | grep -e '^tor-ddos-[0-9]*$' -e '^tor-trust$' |
    while read -r name; do
      saveIpset $name
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066

# check if regular iptables works or if the legacy variant is explicitly needed
ipt="iptables"
set +e
$ipt -nv -L INPUT &>/dev/null
rc=$?
if [[ $rc -ne 0 ]]; then
  if [[ $rc -eq 4 ]]; then
    ipt+="-legacy"
    if ! $ipt -nv -L INPUT 1>/dev/null; then
      echo " $ipt is not working as expected" >&2
      exit 1
    fi
  else
    echo " $ipt is not working as expected" >&2
    exit 1
  fi
fi
set -e

trustlist="tor-trust"      # Tor authorities and snowflake servers
jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding ips to an ipset
prefix=32                  # any ipv4 address of this CIDR block is considered to belong to the same source/owner
# hash and ipset size: 1M if > 32 GiB, 256K if > 2 GiB, default: 64K
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ ${ram} -gt 32 ]]; then
  max=$((2 ** 20))
elif [[ ${ram} -gt 2 ]]; then
  max=$((2 ** 18))
else
  max=$((2 ** 16))
fi
tmpdir=${TORUTILS_TMPDIR:-/var/tmp}

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
  additionalServices
  addTor ${*:-${CONFIGURED_RELAYS:-$(getConfiguredRelays)}}
  $ipt -P INPUT ${RUN_ME_WITH_SAFE_JUMP_TARGET:-$jump}
  trap - INT QUIT TERM EXIT
  ;;
stop)
  saveCertainIpsets
  clearRules
  ;;
update)
  __fill_trustlist
  ;;
test)
  export RUN_ME_WITH_SAFE_JUMP_TARGET="ACCEPT"
  type ipset iptables jq
  $0 start $*
  ;;
save)
  tmpdir=${1:-$tmpdir} saveCertainIpsets
  ;;
*)
  printRuleStatistics $*
  ;;
esac
