#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# addCommon() and addTor() implements a DDoS solution for a Tor relay, the remaining code just parses configs amd maintains ipset content
# https://github.com/toralf/torutils

function addCommon() {
  # allow loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT
  $ipt -A INPUT -p udp --source fe80::/10 --dst ff02::1 -j ACCEPT

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
}

function addTor() {
  __create_ipset $trustlist "maxelem $((2 ** 6))"
  __fill_trustlist &
  for i in 2 4 8; do
    __create_ipset $multilist-$i "maxelem $((2 ** 13))"
  done
  __fill_multilists &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask $prefix"
  for relay in $*; do
    if [[ ! $relay =~ '[' || ! $relay =~ ']' || $relay =~ '.' || ! $relay =~ ':' ]]; then
      echo " relay '$relay' is invalid" >&2
      return 1
    fi
    read -r orip orport <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$relay)
    if [[ $orip == "::" ]]; then
      orip+="/0"
      echo " notice: using global unicast IPv6 address [::]" >&2
    fi
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    local ddoslist="tor-ddos6-$orport" # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "maxelem $max timeout $((24 * 3600)) netmask $prefix"
    __fill_ddoslist &

    # rule 1
    $common --syn -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    for i in 2 4 8; do
      $common --syn -m set --match-set $multilist-$i src -m set ! --match-set $ddoslist src -m connlimit --connlimit-mask $prefix --connlimit-upto $i -j ACCEPT
    done

    # rule 3
    $common $hashlimit --hashlimit-name tor-ddos-$orport --hashlimit-above 6/minute --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j SET --add-set $ddoslist src --exist
    $common -m set --match-set $ddoslist src -j $jump

    # rule 4
    $common -m connlimit --connlimit-mask $prefix --connlimit-above 2 -j $jump

    # rule 5
    $common $hashlimit --hashlimit-name tor-rate-$orport --hashlimit-above 1/hour --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j $jump

    # rule 6
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
  (
    echo 2a0c:dd40:1:b::42 2a0c:dd40:1:b::43 2a0c:dd40:1:b::44 2a0c:dd40:1:b::45 2a0c:dd40:1:b::46 2607:f018:600:8:be30:5bff:fef1:c6fa
    echo 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2001:858:2:2:aabb:0:563b:1526 2610:1c0:0:5::131 2620:13:4000:6000::1000:118
    getent ahostsv6 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -u
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a | select(length > 1) | .[1:]' <<<$relays |
          tr ',' '\n' | grep -F ':' | tr -d ']["'
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function __fill_multilists() {
  sleep 6 # remote is rate limited, let ipv4 get the data first

  # if empty then use old values for now
  for i in 2 4 8; do
    if ipset list -t $multilist-$i | grep -q -F -m 1 'Number of entries: 0'; then
      if [[ -s $tmpdir/$multilist-$i ]]; then
        xargs -r -n 1 -P $jobs ipset add -exist $multilist-$i <$tmpdir/$multilist-$i
      fi
    fi
  done

  # now there's time to update it
  local relays
  if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o -); then
    if [[ $relays =~ 'relays_published' ]]; then
      local sorted
      if sorted=$(
        set -o pipefail
        jq -r '.relays[] | select(.r == true) | .a | select(length > 1) | .[1:]' <<<$relays |
          tr ',' '\n' | grep -F ':' | tr -d '][" ' |
          sort | uniq -c
      ); then
        for i in 2 4 8; do
          awk '$1 > '$i'/2 && $1 <= '$i' { print $2 }' <<<$sorted >$tmpdir/$multilist-$i
          local tmp="temp-ipset6-$i-$((RANDOM))"
          local args=$(ipset save $multilist-$i | head -n 1 | awk '{ $2 = "'$tmp'" }1' | sed -e 's, initval .*,,')
          if ipset $args; then
            xargs -r -n 1 -P $jobs ipset add $tmp <$tmpdir/$multilist-$i
            ipset swap $tmp $multilist-$i
            ipset destroy $tmp
          fi
        done
        awk '{ print $2 }' <<<$sorted >$tmpdir/relays6
      fi
    fi
  fi
}

function __fill_ddoslist() {
  if [[ -s $tmpdir/$ddoslist ]]; then
    ipset flush $ddoslist
    xargs -r -L 1 -P $jobs ipset add -exist $ddoslist <$tmpdir/$ddoslist # -L 1 b/c the inputs are tupels
  fi
  rm -f $tmpdir/$ddoslist
}

function addLocalServices() {
  for service in ${ADD_LOCAL_SERVICES6-}; do
    read -r addr port <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --dst $addr --dport $port --syn -j ACCEPT
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

function setSysctlValues() {
  local current

  if current=$(sysctl -n net.netfilter.nf_conntrack_max); then
    if [[ $current -lt $((2 * max)) ]]; then
      sysctl -q -w net.netfilter.nf_conntrack_max=$((current + 2 * max))
    fi
  fi
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

function getConfiguredRelays6() {
  grep -h -e "^ORPort *" /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null |
    grep -v ' NoListen' |
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
  ipset list -t | grep '^Name: ' | grep -e 'tor-.*6-' -e 'tor-trust6$' | awk '{ print $2 }' |
    while read -r name; do
      saveIpset $name
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

ipt="ip6tables"
trustlist="tor-trust6"     # Tor authorities and snowflake servers
multilist="tor-multi6"     # Tor relay ip addresses hosting > 1 relay
jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding ips to an ipset
prefix=64                  # any ipv6 address of this /block is considered to belong to the same source/owner
# hash and ipset size
if [[ $(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo) -gt 2 ]]; then
  max=$((2 ** 18)) # RAM is bigger than 2 GiB
else
  max=$((2 ** 16)) # default: 65536
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
  addLocalServices
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
  __fill_multilists
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
