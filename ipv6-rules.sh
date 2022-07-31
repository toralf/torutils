#!/bin/bash
# set -x


startFirewall() {
  ip6tables -P INPUT   DROP
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD DROP
  
  # make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP -m comment --comment "$(date)"
  
  # local traffic
  ip6tables -A INPUT --in-interface lo --source ::1 --destination ::1 -j ACCEPT
  ip6tables -A INPUT -p udp --source fe80::/10 --destination ff02::1  -j ACCEPT
  # maybe handle fd00::/8 here too
 
  # Tor
  ipset destroy $denylist 2>/dev/null
  if [[ -s /var/tmp/ipset.$denylist ]]; then
    ipset restore -f /var/tmp/ipset.$denylist
  else
    ipset create $denylist hash:ip timeout $timeout family inet6 netmask 64
  fi

  # Tor authorities are trusted
  allowlist=tor-authorities6
  ipset destroy $allowlist 2>/dev/null
  ipset create $allowlist hash:ip family inet6
  #  get-authority-ips.sh | grep -F ':' | sort | xargs
  for i in 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2001:858:2:2:aabb:0:563b:1526 2607:8500:154::3 2610:1c0:0:5::131 2620:13:4000:6000::1000:118 2a03:4000:43:216:5443:2bff:fe16:c6b5
  do
    ipset add $allowlist $i
  done

  ip6tables -A INPUT -p tcp --destination $oraddr -m set --match-set $allowlist src -j ACCEPT
  for orport in 443 9001
  do
    name=$denylist-$orport
    ip6tables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m recent --name $name --set
    ip6tables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m recent --name $name --update --seconds $seconds --hitcount $hitcount --rttl -j SET --add-set $denylist src
    ip6tables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 64 --connlimit-above $connlimit -j SET --add-set $denylist src
  done
  ip6tables -A INPUT -p tcp --destination $oraddr -m set --match-set $denylist src -j DROP
  for orport in 443 9001
  do
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done
  
  # trust already established connections
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ip6tables -A INPUT -m conntrack --ctstate INVALID             -j DROP
  
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
  sshport=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  ip6tables -A INPUT -p tcp --destination $sshaddr --destination-port ${sshport:-22} -j ACCEPT
}


stopFirewall() {
  ip6tables -F
  ip6tables -X
  ip6tables -Z

  ip6tables -P INPUT   ACCEPT
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD ACCEPT

  ipset save $denylist -f /var/tmp/ipset.$denylist.tmp && mv /var/tmp/ipset.$denylist.tmp /var/tmp/ipset.$denylist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="2a01:4f9:3b:468e::13"
denylist=tor-ddos6
timeout=86400
seconds=300
hitcount=12   # both tries 1x per minute and maybe a tor client is running there too
connlimit=4   # 2 Tor relays at 1 ip address

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
