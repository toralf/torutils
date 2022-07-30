#!/bin/bash
# set -x


#   https://www.cert.org/downloads/IPv6/ip6table_rules.txt
#

startFirewall() {
  ip6tables -P INPUT   DROP
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD DROP
 
  # Tor
  ipset destroy $blacklist 2>/dev/null
  if [[ -s /var/tmp/ipset.$blacklist ]]; then
    ipset restore -f /var/tmp/ipset.$blacklist
  else
    ipset create $blacklist hash:ip timeout $timeout family inet6 netmask 64
  fi

  # Tor
  ip6tables -A INPUT -m set --match-set $blacklist src -j DROP

  # trust already established connections
  ip6tables -A INPUT --match conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "$(date)"
  ip6tables -A INPUT --match conntrack --ctstate INVALID             -j DROP

  # local traffic
  ip6tables -A INPUT --in-interface lo --source ::1 --destination ::1 -j ACCEPT
  ip6tables -A INPUT -p udp --source fe80::/10 --destination ff02::1  -j ACCEPT
  # maybe handle fd00::/8 here too

  # Make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP

  # To
  for orport in 443 9001
  do
    name=$blacklist-$orport
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m recent --name $name --set
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m recent --name $name --update --seconds $seconds --hitcount $hitcount --rttl -j SET --add-set $blacklist src
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 64 --connlimit-above $connlimit -j SET --add-set $blacklist src
  done
  ip6tables -A INPUT -m set --match-set $blacklist src -j DROP
  for orport in 443 9001
  do
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done

  # only needed for Hetzner customer
  # https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
  #
  getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u |\
  while read s
  do
    ip6tables -A INPUT --source $s -j ACCEPT
  done

  # https://github.com/boldsuck/tor-relay-bootstrap/blob/master/etc/iptables/rules.v6
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  ip6tables -A INPUT -p ipv6-icmp                            -j ACCEPT

  # ssh
  sshport=$(grep -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  ip6tables -A INPUT -p tcp --destination $sshaddr --destination-port ${sshport:-22} -j ACCEPT
}


stopFirewall() {
  ip6tables -F
  ip6tables -X
  ip6tables -Z

  ip6tables -P INPUT   ACCEPT
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD ACCEPT

  ipset save $blacklist -f /var/tmp/ipset.$blacklist.tmp && mv /var/tmp/ipset.$blacklist.tmp /var/tmp/ipset.$blacklist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="2a01:4f9:3b:468e::13"
blacklist=tor-ddos6
timeout=86400
seconds=300
hitcount=12   # both tries 1x per minute
connlimit=4   # 2 Tor relays at 1 ip address allowed

# if there're 2 ip addresses then do assume that the 2nd is used for ssh etc.
dev=$(ip -6 route | grep "^default" | awk '{ print $5 }')
sshaddr=$(ip -6 address show dev $dev | grep -w "inet6 .* scope global" | grep -v -w "$oraddr" | awk '{ print $2 }' | cut -f1 -d'/')
if [[ -z $sshaddr ]]; then
  sshaddr=$oraddr
fi

case $1 in
  start)  startFirewall ;;
  stop)   stopFirewall  ;;
esac
