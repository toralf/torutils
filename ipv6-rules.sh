#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function addCommon() {
  ip6tables -P INPUT ${DEFAULT_POLICY_INPUT:-$jump}
  ip6tables -P OUTPUT ACCEPT

  # allow loopback
  ip6tables -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT
  ip6tables -A INPUT -p udp --source fe80::/10 --dst ff02::1 -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j $jump
  ip6tables -A INPUT -m conntrack --ctstate INVALID -j $jump

  # do not touch established connections
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.*:.*:.*$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"::/0"}; do
    ip6tables -A INPUT -p tcp --dst $i --dport ${port:-22} --syn -j ACCEPT
  done

  # ratelimit ICMP echo
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j $jump
  ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
}

function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name hash:ip family inet6 ${2-}"

  if ! $cmd 2>/dev/null; then
    if ! (ipset list -t $name &>/dev/null && saveIpset $name && ipset destroy $name && $cmd); then
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
      jq -r '.relays[] | .a | select(length > 1) | .[1:]' <<<$relays |
        tr ',' '\n' | grep -F ':' | tr -d ']["'
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function __fill_multilist() {
  (
    if [[ -s /var/tmp/$multilist ]]; then
      cat /var/tmp/$multilist
    fi
    if relays=$(
      sleep 4 # let ipv4 get the data first
      curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o -
    ); then
      jq -r '.relays[] | .a | select(length > 1) | .[1:]' <<<$relays |
        tr ',' '\n' | grep -F ':' | tr -d '][" ' |
        sort -u | tee /var/tmp/$multilist.new
      if [[ -s /var/tmp/$multilist.new ]]; then
        mv /var/tmp/$multilist.new /var/tmp/$multilist
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $multilist
}

function __fill_ddoslist() {
  if [[ -f /var/tmp/$ddoslist ]]; then
    cat /var/tmp/$ddoslist |
      xargs -r -L 1 -P $jobs ipset add -exist $ddoslist
    rm /var/tmp/$ddoslist
  fi
}

function addTor() {
  __create_ipset $trustlist
  __fill_trustlist &
  __create_ipset $multilist
  __fill_multilist &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask $prefix --hashlimit-htable-size $max --hashlimit-htable-max $max"
  for relay in $*; do
    if [[ ! $relay =~ '[' || ! $relay =~ ']' || $relay =~ '.' || ! $relay =~ ':' ]]; then
      echo " relay '$relay' cannot be parsed" >&2
      return 1
    fi
    read -r orip orport <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$relay)
    if [[ $orip == "::" ]]; then
      orip+="/0"
      echo " notice: using global unicast IPv6 address [::]" >&2
    fi
    local synpacket="ip6tables -A INPUT -p tcp --dst $orip --dport $orport --syn"

    local ddoslist="tor-ddos6-$orport" # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "timeout $((24 * 3600)) maxelem $max netmask $prefix"
    __fill_ddoslist &

    # rule 1
    $synpacket -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    $synpacket -m set --match-set $multilist src -m connlimit --connlimit-mask 128 --connlimit-upto 8 -j ACCEPT

    # rule 3
    $synpacket $hashlimit --hashlimit-name tor-ddos-$orport --hashlimit-above 6/minute --hashlimit-burst 5 --hashlimit-htable-expire $((2 * 60 * 1000)) -j SET --add-set $ddoslist src --exist
    $synpacket -m set --match-set $ddoslist src -j $jump

    # rule 4
    $synpacket -m connlimit --connlimit-mask 128 --connlimit-above 2 -j $jump

    # rule 5
    $synpacket $hashlimit --hashlimit-name tor-rate-$orport --hashlimit-above 1/hour --hashlimit-burst 1 --hashlimit-htable-expire $((2 * 60 * 1000)) -j $jump

    # rule 6
    $synpacket -j ACCEPT
  done
}

function addLocalServices() {
  local addr
  local port

  for service in ${ADD_LOCAL_SERVICES6-}; do
    read -r addr port <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    ip6tables -A INPUT -p tcp --dst $addr --dport $port --syn -j ACCEPT
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
  ip6tables -A INPUT -m set --match-set $sysmon src -j ACCEPT
}

function setSysctlValues() {
  local current=$(sysctl -n net.netfilter.nf_conntrack_max)
  if [[ $current -lt $max ]]; then
    sysctl -w net.netfilter.nf_conntrack_max=$((current + max))
  fi
}

function clearRules() {
  ip6tables -P INPUT ACCEPT
  ip6tables -P OUTPUT ACCEPT

  ip6tables -F
  ip6tables -X
  ip6tables -Z
}

function printRuleStatistics() {
  date -R
  echo
  ip6tables -nv -L INPUT
}

function getConfiguredRelays6() {
  grep -h -e "^ORPort *" /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null |
    grep -v ' NoListen' |
    grep -P "^ORPort\s+\[[0-9a-f]*:[0-9a-f:]*:[0-9a-f]*\]:\d+\s*" |
    awk '{ print $2 }'
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

function saveAllIpsets() {
  local suffix=${1-}

  ipset list -t | grep '^Name: ' | grep -e 'tor-ddos6-' -e 'tor-multi6$' | awk '{ print $2 }' |
    while read -r name; do
      saveIpset $name $suffix
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

trustlist="tor-trust6"     # Tor authorities and snowflake
multilist="tor-multi6"     # Tor relay ip addresses hosting > 1 relay
jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding ips to an ipset
prefix=64                  # any ipv6 address of this /block is considered to belong to the same source/owner
# hash and ipset size
if [[ $(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo) -gt 2 ]]; then
  max=$((2 ** 20)) # mem is bigger than 2 GiB
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
  addTor ${*:-${CONFIGURED_RELAYS6:-$(getConfiguredRelays6)}}
  trap - INT QUIT TERM EXIT
  ;;
stop)
  saveAllIpsets
  clearRules
  ;;
test)
  export RUN_ME_WITH_SAFE_JUMP_TARGET="ACCEPT"
  $0 start $*
  ;;
update)
  __fill_trustlist
  __fill_multilist
  ;;
save)
  saveAllIpsets ${1-}
  ;;
*)
  printRuleStatistics
  ;;
esac
