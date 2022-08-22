#!/bin/bash
# set -x


function init() {
  # iptables
  ip6tables -P INPUT   DROP
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD DROP
  
  # allow local traffic
  ip6tables -A INPUT --in-interface lo                                -j ACCEPT -m comment --comment "$(date -R)"
  ip6tables -A INPUT -p udp --source fe80::/10 --destination ff02::1  -j ACCEPT
  
  # make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  
  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  ip6tables -A INPUT -p tcp --destination-port ${port:-22} -j ACCEPT
 
  ## ratelimit ICMP echo
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  ip6tables -A INPUT -p ipv6-icmp                            -j ACCEPT
}


function addTor() {
  local allowlist=tor-allow6
  local blocklist=tor-ddos6
  
  ipset create -exist $allowlist hash:ip family inet6
  ipset create -exist $blocklist hash:ip family inet6 timeout 1800

  # (dig +short snowflake-01.torproject.net. AAAA; get-authority-ips.sh | grep -F ':' | sort -n) | xargs
  for i in 2a0c:dd40:1:b::42 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2001:858:2:2:aabb:0:563b:1526 2607:8500:154::3 2610:1c0:0:5::131 2620:13:4000:6000::1000:118
  do
    ipset add -exist $allowlist $i
  done

  for relay in $relays
  do
    local oraddr=$(sed -e 's,:[0-9]*$,,' <<< $relay)
    local orport=$(grep -Po '\d+$' <<< $relay)

    # accept dedicated ip addresses
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $allowlist src -j ACCEPT
    
    # add to blocklist if appropriate
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m hashlimit --hashlimit-name $blocklist --hashlimit-mode srcip --hashlimit-srcmask 128 --hashlimit-above 10/minute --hashlimit-htable-expire 60000 -j SET --add-set $blocklist src --exist
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 128 --connlimit-above 10 -j SET --add-set $blocklist src --exist

    # drop blocklisted
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $blocklist src -j DROP
  
    # handle buggy (?) clients
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m connlimit --connlimit-mask 128 --connlimit-above 2 -j DROP
  
    # accept remaining
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done
  
  # allow already established connections
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ip6tables -A INPUT -m conntrack --ctstate INVALID             -j DROP
}


# only useful for Hetzner customers: https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
function addHetzner() {
  local monlist=hetzner-monlist6

  ipset create -exist $monlist hash:ip family inet6

  getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u |\
  while read i
  do
    ipset add -exist $monlist $i
  done
  ip6tables -A INPUT -m set --match-set $monlist src -j ACCEPT
}


function clearAll() {
  ip6tables -P INPUT   ACCEPT
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD ACCEPT
  
  ip6tables -F
  ip6tables -X
  ip6tables -Z
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
relays="2a01:4f9:3b:468e::13:443   2a01:4f9:3b:468e::13:9001"

case $1 in
  start)  init
          addHetzner
          addTor
          ;;
  stop)   clearAll
          ;;
esac

