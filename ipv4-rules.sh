#!/bin/bash
# set -x


startFirewall() {
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP
  
  # Tor
  ipset destroy $blacklist 2>/dev/null
  if [[ -s /var/tmp/ipset.$blacklist ]]; then
    ipset restore -f /var/tmp/ipset.$blacklist
  else
    ipset create $blacklist hash:ip timeout 86400
  fi

  # Tor
  iptables -A INPUT -m set --match-set $blacklist src -j DROP

  # trust already established connections
  #
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "$(date)"
  iptables -A INPUT -m conntrack --ctstate INVALID             -j DROP

  # local traffic
  iptables -A INPUT --in-interface lo --source 127.0.0.1/8 --destination 127.0.0.1/8 -j ACCEPT

  # Make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP

  # Tor
  for orport in 443 9001
  do
    name=$blacklist-$orport
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m recent --name $name --set
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m recent --name $name --update --seconds $seconds --hitcount $hitcount --rttl -j SET --add-set $blacklist src
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 32 --connlimit-above $connlimit -j SET --add-set $blacklist src
  done
  iptables -A INPUT -m set --match-set $blacklist src -j DROP
  for orport in 443 9001
  do
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done

  # only needed for Hetzner customer
  # https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
  #
  getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u |\
  while read s
  do
    iptables -A INPUT --source $s -j ACCEPT
  done

  ## ratelimit ICMP echo, allow all others
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP

  # ssh
  sshport=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --destination $sshaddr --destination-port ${sshport:-22} -j ACCEPT

  # non-Tor related stats
  port=$(crontab -l -u torproject | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -z "$port" ]] || iptables -A INPUT -p tcp --destination $sshaddr --destination-port $port -j ACCEPT
  port=$(crontab -l -u tinderbox  | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -z "$port" ]] || iptables -A INPUT -p tcp --destination $sshaddr --destination-port $port -j ACCEPT
}


stopFirewall() {
  iptables -F
  iptables -X
  iptables -Z

  iptables -P INPUT   ACCEPT
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD ACCEPT

  ipset save $blacklist -f /var/tmp/ipset.$blacklist.tmp && mv /var/tmp/ipset.$blacklist.tmp /var/tmp/ipset.$blacklist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="65.21.94.13"
blacklist=tor-ddos
timeout=86400
seconds=300
hitcount=12   # both tries 1x per minute
connlimit=4   # 2 Tor relays at 1 ip address allowed

# if there're 2 ip addresses then do assume that the 2nd is used for ssh etc.
dev=$(ip -4 route | grep "^default" | awk '{ print $5 }')
sshaddr=$(ip -4 address show dev $dev | grep -w "inet .* scope global" | grep -v -w "$oraddr" | awk '{ print $2 }' | cut -f1 -d'/')
if [[ -z $sshaddr ]]; then
  sshaddr=$oraddr
fi

case $1 in
  start)  startFirewall ;;
  stop)   stopFirewall  ;;
esac
