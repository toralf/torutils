#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# addCommon() and addTor() implement a DDoS solution for a Tor relay for IPv4
# the remaining code just parses the config and maintains ipset content
# https://github.com/toralf/torutils

function relay_2_ip_and_port() {
  if [[ $relay =~ '[' || $relay =~ ']' || ! $relay =~ '.' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(tr ':' ' ' <<<$relay)
  if [[ -z $orip || -z $orport ]]; then
    return 1
  fi
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
  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
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

  if $cmd 2>/dev/null; then
    return 0
  else
    if saveIpset $name && ipset destroy $name && $cmd; then
      return 0
    else
      return 1
    fi
  fi
}

function __fill_trustlist() {
  # this is intentionally not filled from a saved set at reboot
  (
    # snowflakes
    echo 141.212.118.18 193.187.88.42 193.187.88.43 193.187.88.44 193.187.88.45 193.187.88.46
    # Tor authorities
    echo 45.66.35.11 66.111.2.131 128.31.0.39 131.188.40.189 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118 216.218.219.41 217.196.147.77
    getent ahostsv4 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -uV
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a[0]' <<<$relays |
          sort -V
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function __fill_ddoslist() {
  if [[ -s $tmpdir/$ddoslist ]]; then
    xargs -r -L 1 -P $jobs ipset add -exist $ddoslist <$tmpdir/$ddoslist # -L 1 b/c the inputs are tuples
  fi
}

function addServices() {
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
  $ipt -A INPUT -m set --match-set $sysmon src -j ACCEPT
  {
    (
      echo 188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86
      getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
    ) |
      xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
}

function setSysctlValues() {
  if modinfo nf_conntrack &>/dev/null && ! lsmod | grep -q 'nf_conntrack'; then
    modprobe nf_conntrack
  fi

  sysctl -q -w net.netfilter.nf_conntrack_max=$max || sysctl -q -w net.nf_conntrack_max=$max
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
  $ipt -nv -L INPUT
}

function getConfiguredRelays() {
  # shellcheck disable=SC2045 disable=SC2010
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null | grep -v -F -e '.sample' -e '.bak' -e '~' -e '@'); do
    if grep -q "^ServerTransportListenAddr " $f; then
      grep "^ServerTransportListenAddr " $f |
        awk '{ print $3 }' |
        grep -P "^\d+\.\d+\.\d+\.\d+:\d+$" |
        grep -v '0.0.0.0'
    else
      # OR port and address are defined either together in 1 line or in 2 different lines
      if orport=$(grep "^ORPort *" $f | grep -v -F -e ' NoListen' -e '[' -e ':auto' | grep -P "^ORPort\s+.+\s*"); then
        if grep -q -Po "^ORPort\s+\d+\.\d+\.\d+\.\d+\:\d+\s*" <<<$orport; then
          awk '{ print $2 }' <<<$orport
        elif address=$(grep -P "^Address\s+\d+\.\d+\.\d+\.\d+\s*" $f); then
          echo $(awk '{ print $2 }' <<<$address):$(awk '{ print $2 }' <<<$orport)
        fi
      fi
    fi
  done
}

function bailOut() {
  local rc=$?

  # sigpipe
  if [[ $rc -eq 141 ]]; then
    return 0
  fi

  trap - INT QUIT TERM EXIT
  echo -e "\n Something went wrong, stopping ...\n" >&2
  clearRules
  exit $rc
}

function saveCertainIpsets() {
  [[ -d $tmpdir ]] || return 1

  ipset list -n |
    grep -e '^tor-ddos-[0-9]*$' -e '^tor-trust$' |
    while read -r name; do
      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
      if ipset list $name >$tmpfile; then
        sed -e '1,8d' <$tmpfile >$tmpdir/$name
      fi
      rm $tmpfile
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066
trap '[[ $? -ne 0 ]] && echo "$0 $* unsuccessful" >&2' INT QUIT TERM EXIT
type ipset jq 1>/dev/null

trustlist="tor-trust"            # Tor authorities and snowflake servers
jobs=$((1 + ($(nproc) - 1) / 2)) # parallel jobs of adding ips to an ipset
prefix=32                        # any ipv4 address of this CIDR block is considered to belong to the same source/owner
# hashes and ipset sizes do depend on available RAM in GiB
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ ${ram} -gt 32 ]]; then
  max=$((2 ** 20)) # 1M
elif [[ ${ram} -gt 2 ]]; then
  max=$((2 ** 18)) # 256K
else
  max=$((2 ** 16)) # 64K
fi
tmpdir=${TORUTILS_TMPDIR:-/var/tmp}

action=${1-}
[[ $# -gt 0 ]] && shift

if [[ $action != "update" && $action != "save" ]]; then
  # check if iptables works or if its legacy variant is needed
  ipt="iptables"
  set +e
  $ipt -nv -L INPUT 1>/dev/null
  rc=$?
  set -e
  if [[ $rc -eq 4 ]]; then
    ipt+="-legacy"
    if ! $ipt -nv -L INPUT 1>/dev/null; then
      echo " $ipt is not working" >&2
      exit 1
    fi
  elif [[ $rc -ne 0 ]]; then
    echo " $ipt is not working, rc=$rc" >&2
    exit 1
  fi
fi

case $action in
start)
  setSysctlValues
  trap bailOut INT QUIT TERM EXIT
  clearRules
  jump=${RUN_ME_WITH_SAFE_JUMP_TARGET:-DROP}
  addCommon
  addHetzner
  addServices
  addTor ${*:-${CONFIGURED_RELAYS:-$(getConfiguredRelays)}}
  $ipt -P INPUT $jump
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
  ipset list -n 1>/dev/null
  export RUN_ME_WITH_SAFE_JUMP_TARGET="ACCEPT"
  $0 start $*
  ;;
save)
  saveCertainIpsets
  ;;
*)
  printRuleStatistics
  ;;
esac
