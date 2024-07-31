#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# addCommon() and addTor() implement a DDoS solution for a Tor relay for IPv6
# the remaining code just parses the config and maintains ipset content
# https://github.com/toralf/torutils

function relay_2_ip_and_port() {
  if [[ ! $relay =~ '[' || ! $relay =~ ']' || $relay =~ '.' || ! $relay =~ ':' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$relay)
  if [[ $orip == "::" ]]; then
    orip+="/0"
    echo " notice: using global unicast IPv6 address [::]" >&2
  fi
}

function addCommon() {
  # allow loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT

  # IPv6 Multicast
  $ipt -A INPUT -p udp --source fe80::/10 --dst ff02::/80 -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  $ipt -A INPUT -p tcp ! --syn -m state --state NEW -j $jump
  $ipt -A INPUT -m conntrack --ctstate INVALID -j $jump
  # do not touch established connections
  $ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.*:.*:.*$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"::/0"}; do
    $ipt -A INPUT -p tcp --dst $i --dport ${port:-22} --syn -j ACCEPT
  done

  # ratelimit ICMP echo
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j $jump
  $ipt -A INPUT -p ipv6-icmp -j ACCEPT

  # DHCPv6
  $ipt -A INPUT -p udp --dport 546 -j ACCEPT
}

function addTor() {
  __create_ipset $trustlist "maxelem $((2 ** 6))"
  __fill_trustlist &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask $prefix"
  for relay in $*; do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    local ddoslist="tor-ddos6-$orport" # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "maxelem $max timeout $((24 * 3600)) netmask $prefix"
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
  local cmd="ipset create -exist $name hash:ip family inet6 ${2-}"

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
    echo 2607:f018:600:8:be30:5bff:fef1:c6fa 2a0c:dd40:1:b::42
    # Tor authorities
    echo 2001:470:164:2::2 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2610:1c0:0:5::131 2620:13:4000:6000::1000:118 2a02:16a8:662:2203::1
    getent ahostsv6 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -u
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a | select(length > 1) | .[1:]' <<<$relays |
          tr ',' '\n' | grep -F ':' | tr -d ']["' |
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
  for service in ${ADD_LOCAL_SERVICES6-}; do
    read -r addr port <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --dst $addr --dport $port --syn -j ACCEPT
  done

  # remote-address>local-port
  for service in ${ADD_REMOTE_SERVICES6-}; do
    read -r addr port <<<$(sed -e 's,]>, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --src $addr --dport $port --syn -j ACCEPT
  done
}

function addHetzner() {
  local sysmon="hetzner-sysmon6"

  __create_ipset $sysmon
  {
    (
      echo 2a01:4f8:0:a101::5:1 2a01:4f8:0:a101::6:1 2a01:4f8:0:a101::6:2 2a01:4f8:0:a101::6:3 2a01:4f8:0:a112::c:1
      getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
    ) |
      xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
  $ipt -A INPUT -m set --match-set $sysmon src -j ACCEPT
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

# OR port + address are defined in 1 line
function getConfiguredRelays6() {
  grep -h -e "^ORPort *" /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null |
    grep -v -F -e ' NoListen' -e ':auto' |
    grep -P "^ORPort\s+\[[0-9a-f]*:[0-9a-f:]*:[0-9a-f]*\]:\d+\s*" |
    awk '{ print $2 }'
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
  ipset list -n | grep -e '^tor-ddos6-[0-9]*$' -e '^tor-trust6$' |
    while read -r name; do
      saveIpset $name
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066

if type ip6tables-legacy 1>/dev/null; then
  ipt="ip6tables-legacy"
elif type ip6tables 1>/dev/null; then
  ipt="ip6tables"
else
  echo "can't find ip6tables executable" >&1
fi
trustlist="tor-trust6"     # Tor authorities and snowflake servers
jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding ips to an ipset
prefix=80                  # any ipv6 address of this CIDR block is considered to belong to the same source/owner
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
  addCommon
  addHetzner
  additionalServices
  addTor ${*:-${CONFIGURED_RELAYS6:-$(getConfiguredRelays6)}}
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
  $0 start $*
  ;;
save)
  tmpdir=${1:-$tmpdir} saveCertainIpsets
  ;;
*)
  printRuleStatistics $*
  ;;
esac
