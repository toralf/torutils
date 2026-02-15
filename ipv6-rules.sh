#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# addCommon() and addTor() implement a DDoS solution for a Tor relay for IPv6
# the remaining code just parses the config and maintains ipset content
# https://github.com/toralf/torutils

function relay_2_ip_and_port() {
  if [[ ! $relay =~ '[' || ! $relay =~ ']' || $relay =~ '.' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$relay)
  if [[ -z $orip || -z $orport ]]; then
    return 1
  fi
}

function addCommon() {
  # allow loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "DDoS IPv6 $(date -R)" -j ACCEPT

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
  $ipt -A INPUT -p ipv6-icmp -j ACCEPT

  # DHCPv6
  $ipt -A INPUT -p udp --dport 546 -j ACCEPT
}

function addTor() {
  __create_ipset $trustlist "maxelem 64"
  __fill_trustlist &

  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    local ddoslist="tor-ddos6-$orport" # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "maxelem $max timeout $((24 * 3600))"
    __load_ipset $ddoslist &

    # rule 1 (only once for all Tor instances at the same ip)
    local trust_rule="INPUT -p tcp --dst $orip --syn -m set --match-set $trustlist src -j ACCEPT"
    if ! $ipt -C $trust_rule 2>/dev/null; then
      $ipt -A $trust_rule
    fi

    # rule 2
    local manuallist=${ddoslist//ddos/manual}
    __create_ipset $manuallist "maxelem $max timeout $((24 * 3600))" "hash:net"
    # "refresh" an /64 entry in this ipset before (partially rule 3)
    $common -m set --match-set $manuallist src -m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask 64 --hashlimit-name tor-manual-$orport --hashlimit-above 9/minute --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j SET --add-set $manuallist src --exist
    $common -m set --match-set $manuallist src -j $jump
    __load_ipset $manuallist &

    # rule 3
    $common -m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask 72 --hashlimit-name tor-ddos-$orport --hashlimit-above 9/minute --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j SET --add-set $ddoslist src --exist
    $common -m set --match-set $ddoslist src -j $jump

    # rule 4
    $common -m connlimit --connlimit-mask 72 --connlimit-above 8 -j $jump

    # rule 5
    $common --syn -j ACCEPT
  done
}

function __create_ipset() {
  local name=$1
  local hash=${3:-"hash:ip netmask 72"}
  local cmd="ipset create -exist $name $hash family inet6 $2"

  if $cmd 2>/dev/null; then
    return 0
  else
    if ipset destroy $name && $cmd; then
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
    echo 2a0c:dd40:1:b::42 2607:f018:600:8:be30:5bff:fef1:c6fa
    # Tor authorities
    echo 2001:470:164:2::2 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2610:1c0:0:5::131 2620:13:4000:6000::1000:118 2a02:16a8:662:2203::1
    getent ahostsv6 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -uV
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a | select(length > 1) | .[1:]' <<<$relays |
          tr ',' '\n' | grep -F ':' | tr -d ']["' |
          sort -V
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function __load_ipset() {
  if [[ -s $tmpdir/$1 ]]; then
    xargs -r -L 1 -P $jobs ipset add -exist $1 <$tmpdir/$1 # -L 1 b/c the inputs are tuples
  fi
}

# certain hosters provide for each system a /64 hostmask instead of the /56 hostmask of rule 3
# but iptables works with hash:ip only, not with hash:net, so rule 3 cannot be implemented
# to handle different hostmasks (e.g. /56 and a/64) in an easily backward-compatible manner
#
# solution:
# for all /56 hostmask entries of the same /64 hostmask add this /64 entry to the "manual" ipset
function fillManualIpsets() {
  ipset list -n ${1-} |
    grep "^tor-ddos6-" |
    while read -r ddoslist; do
      entries=$(
        # Hetzner, GOIAS CONECT TELECOM EIRELI
        ipset list $ddoslist |
          sed '1,8d' |
          grep -e "^2a01:4f[89]" -e "^2804:4310" |
          awk '{ print $1 }' |
          cut -f 1-4 -d ':' |
          sort -u
      )

      manuallist=${ddoslist//ddos/manual}
      xargs -r -P $jobs -I{} ipset add -exist $manuallist {}::/64 <<<$entries
    done
}

function addServices() {
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

  __create_ipset $sysmon "maxelem 64"
  $ipt -A INPUT -m set --match-set $sysmon src -j ACCEPT
  {
    (
      echo 2a01:4f8:0:a101::5:1 2a01:4f8:0:a101::6:1 2a01:4f8:0:a101::6:2 2a01:4f8:0:a101::6:3 2a01:4f8:0:a112::c:1
      getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
    ) |
      xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
}

function clearRules() {
  $ipt -P INPUT ACCEPT

  $ipt -F INPUT
  $ipt -Z INPUT
}

function printRuleStatistics() {
  date -R
  echo
  $ipt -nv -L INPUT
}

function getConfiguredRelays6() {
  # shellcheck disable=SC2045 disable=SC2010
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null | grep -v -F -e '.sample' -e '.bak' -e '~' -e '@'); do
    if grep -q "^ServerTransportListenAddr " $f; then
      grep "^ServerTransportListenAddr " $f |
        awk '{ print $3 }' |
        grep -P "^\[[0-9a-f]*:[0-9a-f:]*:[0-9a-f]*\]:\d+$"
    else
      grep -v -F -e ' NoListen' -e ':auto' $f |
        grep -P "^ORPort\s+\[[0-9a-f]*:[0-9a-f:]*:[0-9a-f]*\]:\d+\s*" |
        awk '{ print $2 }'
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
    grep -e '^tor-ddos6-[0-9]*$' -e '^tor-manual6-[0-9]*$' -e '^tor-trust6$' |
    while read -r name; do
      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
      if ipset list $name >$tmpfile; then
        sed -e '1,8d' <$tmpfile |
          sort >$tmpdir/$name
      fi
      rm $tmpfile
    done
}

#######################################################################
set -eu
set -m # allow fg in shell scripts
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066
trap '[[ $? -ne 0 ]] && echo "$0 $* unsuccessful" >&2' INT QUIT TERM EXIT
type ipset jq >/dev/null

trustlist="tor-trust6"           # Tor authorities and snowflake servers
jobs=$((1 + ($(nproc) - 1) / 8)) # parallel jobs of adding ips to an ipset
# hashes and ipsets are sized with respect to the available RAM in GiB
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ ${ram} -gt 1 ]]; then
  max=$((2 ** 19)) # 512K
else
  max=$((2 ** 17)) # 128K
fi
tmpdir=${TORUTILS_TMPDIR:-/var/tmp}

action=${1-}
[[ $# -gt 0 ]] && shift

if [[ $action != "update" && $action != "save" ]]; then
  # check if iptables works or if its legacy variant is needed
  ipt="ip6tables"
  set +e
  $ipt -nv -L INPUT >/dev/null
  rc=$?
  set -e
  if [[ $rc -eq 4 ]]; then
    ipt+="-legacy"
    if ! $ipt -nv -L INPUT >/dev/null; then
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
  trap bailOut INT QUIT TERM EXIT
  clearRules
  jump=${RUN_ME_WITH_SAFE_JUMP_TARGET:-DROP}
  addCommon
  addHetzner
  addServices
  addTor ${*:-${CONFIGURED_RELAYS6-$(getConfiguredRelays6)}}
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
  ipset list -n >/dev/null
  RUN_ME_WITH_SAFE_JUMP_TARGET="ACCEPT" $0 start $*
  ;;
save)
  saveCertainIpsets
  ;;
manual)
  fillManualIpsets
  ;;
*)
  printRuleStatistics
  ;;
esac

while fg 2>/dev/null; do
  :
done
