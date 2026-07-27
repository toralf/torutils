#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# implement a DDoS solution for a Tor relay for IPv6
# https://github.com/toralf/torutils

function addCommon() {
  # loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "DDoS IPv6 $(date -R)" -j ACCEPT

  # do not touch established connections
  $ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  $ipt -A INPUT -m conntrack --ctstate INVALID -j $jump

  # make sure NEW incoming tcp connections are SYN packets
  $ipt -A INPUT -p tcp ! --syn -m conntrack --ctstate NEW -j $jump

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.*:.*:.*$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"::/0"}; do
    $ipt -A INPUT -p tcp --dst $i --dport ${port:-22} -j ACCEPT
  done

  # manually filled from outsite
  __create_ipset $manuallist "hash:net timeout $((24 * 3600))"
  $ipt -A INPUT -m set --match-set $manuallist src -j $jump

  # see RFC 4890

  # IPv6 Path MTU Discovery
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type time-exceeded -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type parameter-problem -j ACCEPT

  # Neighbor Discovery Protocol - prevent Remote-Spoofing
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -m hl --hl-eq 255 -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -m hl --hl-eq 255 -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j ACCEPT

  # ping
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s --limit-burst 10 -j ACCEPT

  # not at a server
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type redirect -j $jump

  # DHCPv6
  $ipt -A INPUT -p udp --dport 546 -j ACCEPT

  # IPv6 Multicast
  $ipt -A INPUT -p udp --source fe80::/10 --dst ff02::/80 -j ACCEPT

  # default policy
  $ipt -P INPUT $jump
}

function addTor() {
  # rule 1 (trust Tor authorities) is ORPort independend
  __create_ipset $trustlist "hash:ip maxelem 64"
  fill_trustlist &
  $ipt -A INPUT -p tcp -m set --match-set $trustlist src -j ACCEPT

  # strategy:
  #   - block a single system based on its netmask (hint: this is not the whole provider subnet itself)
  #   - fallback is a /128 netmask (can be overruled by NETMASK6_OVERRULE)
  #   - the hoster lists here are almost incomplete, collected are hosters from where attacks were observed in the past
  #   - regular check the /128 ipset for updates of the hoster64 list:
  #     awk '{ print $1 }' /var/tmp/tor-ddos128-* | sort -V
  #     but watch the /128 hash too:
  #     cat /proc/net/ip6t_hashlimit/tor-ddos128-*-x | cut -f 2 -d ' ' | cut -f 1 -d '-' | sort -V | uniq -c | sort -bn

  # /64 netmask
  __create_ipset $hoster64list "hash:net maxelem 64"
  # shellcheck disable=SC2034
  while read -r h comment; do
    ipset add -exist $hoster64list $h
  done <<EOF
2a00:1fa0:8000::/33 # MTS PJSC
2607:8500::/32 # Rethem Hosting LLC
2a00:63c0::/29 # IPAX GmbH
2a01:4f8::/31 # Hetzner
2a0d:bbc7::/32 # QuxLabs AB
2c0f:fc89::/32 # Etisalat Misr (e& Egypt)
EOF

  # common hash limit options
  local hashlimit_opts="--hashlimit-mode srcip,dstport --hashlimit-above 8/minute --hashlimit-burst 8 --hashlimit-htable-max $max --hashlimit-htable-size $((max / 4)) --hashlimit-htable-expire $((2 * 60 * 1000))"
  local hashlimit_opts_x="--hashlimit-mode srcip,dstport --hashlimit-above 16/hour --hashlimit-burst 16 --hashlimit-htable-max $max --hashlimit-htable-size $((max / 4)) --hashlimit-htable-expire $((60 * 60 * 1000))"

  # run over all relays
  # a separate CHAIN for each relay is an option, but rather wrt readability b/c the majority of packets is handled by ct
  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    # rule 2 (catch DDoS)

    # /64 netmask
    local ddoslist64="tor-ddos64-$orport"
    __create_ipset $ddoslist64 "hash:ip netmask 64 maxelem $max timeout 86400"

    $common -m set --match-set $hoster64list src \
      -m hashlimit --hashlimit-srcmask 64 --hashlimit-name $ddoslist64 $hashlimit_opts -j SET --add-set $ddoslist64 src --exist
    $common -m set --match-set $hoster64list src \
      -m hashlimit --hashlimit-srcmask 64 --hashlimit-name $ddoslist64-x $hashlimit_opts_x -j SET --add-set $ddoslist64 src --exist
    $common -m set --match-set $ddoslist64 src -j $jump

    # default netmask, usually /128
    local ddoslist128="tor-ddos128-$orport"
    __create_ipset $ddoslist128 "hash:ip netmask ${NETMASK6_OVERRULE:-128} maxelem $max timeout 86400"

    $common -m set ! --match-set $hoster64list src \
      -m hashlimit --hashlimit-srcmask ${NETMASK6_OVERRULE:-128} --hashlimit-name $ddoslist128 $hashlimit_opts -j SET --add-set $ddoslist128 src --exist
    $common -m set ! --match-set $hoster64list src \
      -m hashlimit --hashlimit-srcmask ${NETMASK6_OVERRULE:-128} --hashlimit-name $ddoslist128-x $hashlimit_opts_x -j SET --add-set $ddoslist128 src --exist
    $common -m set --match-set $ddoslist128 src -j $jump

    # rule 3 (only 1 connection from each of up to 8 Tor relays per ip address)

    $common -m set --match-set $hoster64list src -m connlimit --connlimit-mask 64 --connlimit-above 8 -j $jump
    $common -m set ! --match-set $hoster64list src -m connlimit --connlimit-mask ${NETMASK6_OVERRULE:-128} --connlimit-above 8 -j $jump

    # rule 4

    $common -j ACCEPT
  done
}

function relay_2_ip_and_port() {
  if [[ ! $relay =~ '[' || ! $relay =~ ']' || $relay =~ '.' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$relay)
  if [[ -z $orip ]]; then
    echo " relay '$relay' has no valid ip" >&2
    return 1
  fi
  if [[ -z $orport ]]; then
    echo " relay '$relay' has no valid port" >&2
    return 1
  fi
}

function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name $2 family inet6"

  local load=0 # whether to load from saved file or not
  if ! ipset list -t $name &>/dev/null; then
    load=1
  fi

  if ! $cmd 2>/dev/null; then
    if ! ipset destroy $name || ! $cmd; then
      return 1
    fi
    load=1
  fi

  if [[ $load -eq 1 ]]; then
    if [[ -s $tmpdir/$name ]]; then
      xargs -r -L 1 -P $jobs ipset add -exist $1 <$tmpdir/$name & # -L 1 b/c the inputs are tuples
    fi
  fi
}

function fill_trustlist() {
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

function addServices() {
  local addr port service

  # local-address:local-port
  for service in ${ADD_LOCAL_SERVICES6-}; do
    read -r addr port <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
  done

  # remote-address>local-port
  for service in ${ADD_REMOTE_SERVICES6-}; do
    read -r addr port <<<$(sed -e 's,]>, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --src $addr --dport $port -j ACCEPT
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
        grep -E "^\[[0-9a-fA-F:]{2,39}\]:[0-9]+$"
    else
      grep -v -F -e ' NoListen' -e ':auto' $f |
        grep -E "^ORPort[[:space:]]+\[[0-9a-fA-F]*:[0-9a-fA-F:]*:[0-9a-fA-F]*\]:[0-9]+[[:space:]]*" |
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
    grep -E -e '^tor-ddos64-[0-9]+$' -e '^tor-ddos128-[0-9]+$' -e "^$manuallist$" -e "^$hoster64list$" |
    while read -r name; do
      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
      if ipset list $name >$tmpfile; then
        if sed -i -e '1,8d' $tmpfile; then
          mv $tmpfile $tmpdir/$name
        fi
      fi
      rm -f $tmpfile
    done
}

#######################################################################
set -eu # no -f
set -m  # allow fg in shell scripts
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066
trap '[[ $? -ne 0 ]] && echo "$0 $* unsuccessful" >&2' INT QUIT TERM EXIT
type curl ipset jq >/dev/null

hoster64list="tor-hoster64"      # network from where ip addreses are considerd to have /64 network prefix
manuallist="tor-manual6"         # to be filled manually from outside
trustlist="tor-trust6"           # Tor authorities and snowflake servers
jobs=$((1 + ($(nproc) - 1) / 8)) # parallel jobs of adding ips to an ipset
# hashes and ipsets are sized with respect to the available RAM in GiB
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ ${ram} -gt 1 ]]; then
  max=$((2 ** 20)) # 1M
else
  max=$((2 ** 18)) # 256K
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
  trap - INT QUIT TERM EXIT
  ;;
stop)
  clearRules
  ;;
update)
  fill_trustlist
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
