#!/bin/bash
# set -x


function addCommon() {
  ip6tables -P INPUT  DROP
  ip6tables -P OUTPUT ACCEPT

  # allow loopback
  ip6tables -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT
  ip6tables -A INPUT -p udp --source fe80::/10 --dst ff02::1 -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  ip6tables -A INPUT -m conntrack --ctstate INVALID -j DROP

  # do not touch established connections
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config | awk '{ print $2 }')
  local addr=$(grep -m 1 -E "^ListenAddress\s+.+$"  /etc/ssh/sshd_config | awk '{ print $2 }' | grep -F ':')
  ip6tables -A INPUT -p tcp --dst ${addr:-"::/0"} --dport ${port:-22} -j ACCEPT

  ## ratelimit ICMP echo
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  ip6tables -A INPUT -p ipv6-icmp                            -j ACCEPT
}


function __fill_trustlist() {
  (
    echo "2a0c:dd40:1:b::42 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2001:858:2:2:aabb:0:563b:1526 2607:8500:154::3 2610:1c0:0:5::131 2620:13:4000:6000::1000:118"
    getent ahostsv6 snowflake-01.torproject.net. | awk '{ print $1 }' | sort -un | xargs
    if jq --help &>/dev/null; then
      curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a | select(length > 1) | .[1]' | tr -d '][' | sort -n | xargs
    else
      { echo "please install package jq to have always the latest ip adddresses of the Tor authorities" >&2 ; }
    fi
  ) | xargs -r -n 1 -P 20 ipset add -exist $trustlist
}


function addTor() {
  local trustlist=tor-trust6

  ipset create -exist $trustlist hash:ip family inet6
  __fill_trustlist &

  hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask 128 --hashlimit-htable-expire $(( 1000*60*1 )) --hashlimit-htable-size $((2**20)) --hashlimit-htable-max $((2**20))"
  for relay in $*
  do
    read -r orip orport <<< $(sed -e 's,]:, ,' <<< $relay | tr '[' ' ')
    local synpacket="ip6tables -A INPUT -p tcp --dst $orip --dport $orport --syn"
    local blocklist="tor-ddos6-$orport"
    ipset create -exist $blocklist hash:ip family inet6 timeout $(( 30*60 )) hashsize $((2**20))

    # rule 1
    $synpacket -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    $synpacket $hashlimit --hashlimit-name tor-block-$orport --hashlimit-above 5/minute --hashlimit-burst 4 -j SET --add-set $blocklist src --exist
    $synpacket -m set --match-set $blocklist src -j DROP

    # rule 3
    $synpacket $hashlimit --hashlimit-name tor-limit-$orport --hashlimit-above 1/minute --hashlimit-burst 1 -j DROP

    # rule 4
    $synpacket -m connlimit --connlimit-mask 128 --connlimit-above 4 -j DROP

    # rule 5
    $synpacket -j ACCEPT
  done
}


function addLocalServices() {
  local addr
  local port

  for service in ${ADD_LOCAL_SERVICES6:-}
  do
    read -r addr port <<< $(sed -e 's,]:, ,' <<< $service | tr '[' ' ')
    ip6tables -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
  done
}


function addHetzner() {
  local sysmon=hetzner-sysmon6

  ipset create -exist $sysmon hash:ip family inet6
  # getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u | xargs
  for i in 2a01:4f8:0:a101::5:1 2a01:4f8:0:a101::6:1 2a01:4f8:0:a101::6:2 2a01:4f8:0:a101::6:3 2a01:4f8:0:a112::c:1
  do
    ipset add -exist $sysmon $i
  done
  ip6tables -A INPUT -m set --match-set $sysmon src -j ACCEPT
}


function clearAll() {
  ip6tables -P INPUT  ACCEPT
  ip6tables -P OUTPUT ACCEPT

  ip6tables -F
  ip6tables -X
  ip6tables -Z
}


function printFirewall()  {
  date -R
  echo
  ip6tables -nv -L INPUT
}


function getConfiguredRelays6()  {
  sed 's,#.*,,' /etc/tor/torrc* | grep -P "^ORPort\s+[0-9a-f:\[\]]+:\d+\s*$" | awk '{ print $2 }'
}


function bailOut()  {
  trap - INT QUIT TERM EXIT

  echo "Something went wrong, stopping ..."
  clearAll
  exit 1
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

trap bailOut INT QUIT TERM EXIT
case ${1:-} in
  start)  clearAll
          addCommon
          addHetzner
          addLocalServices
          addTor ${CONFIGURED_RELAYS6:-$(getConfiguredRelays6)}
          ;;
  stop)   clearAll
          ;;
  *)      printFirewall
          ;;
esac
trap - INT QUIT TERM EXIT
