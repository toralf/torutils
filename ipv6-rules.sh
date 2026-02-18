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
  # trust them, so do not narrow down to the Tor ORport
  __create_ipset $trustlist "hash:ip maxelem 64"
  __fill_trustlist &

  # ipv6 prefixes known to provide systems with a /64 hostmask
  hoster64list="tor-hoster64"
  __create_ipset $hoster64list "hash:net maxelem 64"
  ipset flush $hoster64list
  for h in "2a01:4f8::/31" "2a12:a800::/29"; do
    ipset add -exist $hoster64list $h
  done

  # ipv6 prefixes known to provide systems with a /56 hostmask
  hoster72list="tor-hoster72"
  __create_ipset $hoster72list "hash:net maxelem 64"
  # shellcheck disable=SC2043
  ipset flush $hoster72list
  for h in ; do
    ipset add -exist $hoster72list $h
  done

  # common for each hostmask
  hashlimit_opts="--hashlimit-mode srcip,dstport --hashlimit-above 9/minute --hashlimit-burst 1 --hashlimit-htable-expire 120000"

  # run over all relays
  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    # rule 1 (trust Tor authorities independed of the ORport)

    local trust_rule="INPUT -p tcp --dst $orip --syn -m set --match-set $trustlist src -j ACCEPT"
    if ! $ipt -C $trust_rule 2>/dev/null; then
      $ipt -A $trust_rule
    fi

    # rule 2 (catch DDoS)

    # idea: check wrt known hosters providing /64 or /56 hostmask respectively, otherwise assume a /48 hostmask

    # /64 hostmask
    local ddoslist64="tor-ddos64-$orport"
    __create_ipset $ddoslist64 "hash:ip netmask 64 maxelem $max timeout 86400"
    __load_ipset $ddoslist64 &

    $common -m set --match-set $hoster64list src \
      -m hashlimit --hashlimit-srcmask 64 --hashlimit-name $ddoslist64 $hashlimit_opts -j SET --add-set $ddoslist64 src --exist
    $common -m set --match-set $ddoslist64 src -j $jump

    # /56 hostmask
    local ddoslist72="tor-ddos72-$orport"
    __create_ipset $ddoslist72 "hash:ip netmask 72 maxelem $max timeout 86400"
    __load_ipset $ddoslist72 &

    $common -m set --match-set $hoster72list src \
      -m hashlimit --hashlimit-srcmask 72 --hashlimit-name $ddoslist72 $hashlimit_opts -j SET --add-set $ddoslist72 src --exist
    $common -m set --match-set $ddoslist72 src -j $jump

    # /48 hostmask
    local ddoslist80="tor-ddos80-$orport"
    __create_ipset $ddoslist80 "hash:ip netmask 80 maxelem $max timeout 86400"
    __load_ipset $ddoslist80 &

    $common -m set ! --match-set $hoster64list src -m set ! --match-set $hoster72list src \
      -m hashlimit --hashlimit-srcmask 80 --hashlimit-name $ddoslist80 $hashlimit_opts -j SET --add-set $ddoslist80 src --exist
    $common -m set --match-set $ddoslist80 src -j $jump

    # rule 3 (only 1 connection from up to 8 (currently allowed) Tor relays originating from the same source)

    $common -m set --match-set $hoster64list src -m connlimit --connlimit-mask 64 --connlimit-above 8 -j $jump
    $common -m set --match-set $hoster72list src -m connlimit --connlimit-mask 72 --connlimit-above 8 -j $jump
    $common -m set ! --match-set $hoster64list src -m set ! --match-set $hoster72list src -m connlimit --connlimit-mask 80 --connlimit-above 8 -j $jump

    # rule 4

    $common --syn -j ACCEPT
  done
}

function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name $2 family inet6"

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
  # this is intentionally not loaded from a saved set
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

  __create_ipset $sysmon "hash:ip maxelem 64"
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
    grep -e '^tor-trust6$' -e '^tor-ddos64-[0-9]*$' -e '^tor-ddos72-[0-9]*$' -e '^tor-ddos80-[0-9]*$' |
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
*)
  printRuleStatistics
  ;;
esac

while fg 2>/dev/null; do
  :
done
