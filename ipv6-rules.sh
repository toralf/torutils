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

  # tarpit
  __create_ipset $tarpitset "netmask $netmask maxelem $max timeout 86400"
  $ipt -A INPUT -m set --match-set $tarpitset src -j $jump

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
  $ipt -A INPUT -p udp --sport 547 --dport 546 -j ACCEPT

  # IPv6 Multicast
  $ipt -A INPUT -p udp --source fe80::/10 --dst ff02::/80 -j ACCEPT
}

function addTor() {

  # rule 1 (trust Tor authorities) is ORPort independend

  __create_ipset $trustset
  $ipt -A INPUT -p tcp -m set --match-set $trustset src -j ACCEPT
  fill_trustset &

  local hashlimit_opts="--hashlimit-mode srcip,dstport --hashlimit-htable-max $max --hashlimit-htable-size $((max / 4)) --hashlimit-srcmask $netmask"
  local hashlimit_opts_2m="$hashlimit_opts --hashlimit-above 8/minute --hashlimit-burst 8 --hashlimit-htable-expire $((2 * 60 * 1000))"
  local hashlimit_opts_1h="$hashlimit_opts --hashlimit-above 24/hour --hashlimit-burst 24 --hashlimit-htable-expire $((60 * 60 * 1000))"

  # run over all <relay, orport> tuples
  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    # rule 2 (catch DDoS)

    local ddosset="torutils-ddos-v6-$orport-$netmask"
    __create_ipset $ddosset "netmask $netmask maxelem $max timeout 86400"

    $common \
      -m hashlimit --hashlimit-name $ddosset-2m $hashlimit_opts_2m \
      -j SET --add-set $ddosset src --exist
    $common \
      -m hashlimit --hashlimit-name $ddosset-1h $hashlimit_opts_1h \
      -j SET --add-set $ddosset src --exist
    $common -m set --match-set $ddosset src -j $jump

    # rule 3 (only 1 connection from each of up to 8 Tor relays per ip address)

    $common -m connlimit --connlimit-mask $netmask --connlimit-above 8 -j $jump

    # rule 4

    $common -j ACCEPT
  done
}

function addTarpit() {
  $ipt -A INPUT -p tcp -j SET --add-set $tarpitset src --exist

  # default policy
  $ipt -P INPUT $jump
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
  local name=${1?NAME NOT GIVEN}
  local family="inet6"
  local cmd="ipset create -exist $name hash:ip ${2-} family $family"

  if $cmd 2>/dev/null; then
    return 0
  fi

  if ! ipset destroy $name; then
    return 1
  fi

  if ! $cmd 2>/dev/null; then
    return 1
  fi
}

function fill_trustset() {
  (
    # snowflakes
    echo 2a0c:dd40:1:b::42 2607:f018:600:8:be30:5bff:fef1:c6fa
    # Tor authorities
    echo 2001:470:164:2::2 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2610:1c0:0:5::131 2620:13:4000:6000::1000:118 2a02:16a8:662:2203::1
    getent ahostsv6 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -uV
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustset
}

function addServices() {
  local addr port service

  # local-address:local-port(s)
  for service in ${TORUTILS_LOCAL_SERVICES_V6-}; do
    read -r addr port <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    if [[ $port =~ "," ]]; then
      $ipt -A INPUT -p tcp --dst $addr -m multiport --dports $port -j ACCEPT
    else
      $ipt -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
    fi
  done

  # remote-address>local-port
  for service in ${TORUTILS_REMOTE_SERVICES_V6-}; do
    read -r addr port <<<$(sed -e 's,]>, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --src $addr --dport $port -j ACCEPT
  done
}

function addHetzner() {
  # detect Hetzner
  if ! host $(curl -4 --max-time 2 -s https://ip.hetzner.com) | grep -q -e 'your-server.de' -e 'hetzner'; then
    return
  fi

  local sysmon="torutils-hetznersysmon-v6"

  __create_ipset $sysmon
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

function getConfiguredRelays_v6() {
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

#######################################################################
set -eu # no -f
set -m  # allow fg in shell scripts
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066
trap '[[ $? -ne 0 ]] && echo "$0 $* unsuccessful" >&2' INT QUIT TERM EXIT
type curl ipset jq >/dev/null

jobs=$((1 + $(nproc) / 4))     # parallel jobs of adding ips to an ipset
tarpitset="torutils-tarpit-v6" # last rule or can be filled manually from outside
trustset="torutils-trust-v6"   # Tor authorities and snowflake servers

# hashes and ipsets are sized with respect to RAM in GiB
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ $ram -gt 4 ]]; then
  max=$((2 ** 20)) # 1M
elif [[ $ram -gt 1 ]]; then
  max=$((2 ** 19)) # 512 K
else
  max=$((2 ** 18)) # 256K, 40 MiB per hash, 75 MiB for conntrack
fi
netmask=${TORUTILS_NETMASK_V6:-64}

ipt="ip6tables"

action=${1-}
[[ $# -gt 0 ]] && shift
case $action in
start)
  trap bailOut INT QUIT TERM EXIT
  clearRules
  jump=${TORUTILS_SAVE_RUN:-DROP}
  addCommon
  addHetzner
  addServices
  addTor ${*:-${TORUTILS_RELAYS_V6-$(getConfiguredRelays_v6)}}
  addTarpit
  trap - INT QUIT TERM EXIT
  ;;
stop)
  clearRules
  ;;
update)
  fill_trustset
  ;;
test)
  ipset list -n >/dev/null
  TORUTILS_SAVE_RUN="ACCEPT" $0 start $*
  ;;
*)
  printRuleStatistics
  ;;
esac

# wait till all bg jobs finished
while fg &>/dev/null; do
  :
done
