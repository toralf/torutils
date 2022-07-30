#!/bin/bash
# set -x


startFirewall() {
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP

  oraddr="65.21.94.13"

  # trust already established connections
  #
  iptables -A INPUT --match conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "$(date)"
  iptables -A INPUT --match conntrack --ctstate INVALID             -j DROP

  # Allow localhost traffic
  iptables -A INPUT --in-interface lo -j ACCEPT

  # Make sure NEW incoming tcp connections are SYN packets; otherwise we need to drop them.
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP

  # Tor
  if ! ipset list $blacklist &>/dev/null; then
    if [[ -s /var/tmp/ipset.$blacklist ]] && head -n 1 /var/tmp/ipset.$blacklist | grep -q "timeout $timeout"; then
      ipset restore -f /var/tmp/ipset.$blacklist
    else
      ipset create $blacklist hash:ip timeout 86400
    fi
  fi

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

  primary=$(ifconfig $link | grep ' inet ' | awk '{ print $2 }')
  
  # ssh
  sshport=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --destination $primary --destination-port ${sshport:-22} -j ACCEPT

  # non-Tor related stats
  port=$(crontab -l -u torproject | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -z "$port" ]] || iptables -A INPUT -p tcp --destination $primary --destination-port $port -j ACCEPT
  port=$(crontab -l -u tinderbox  | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -z "$port" ]] || iptables -A INPUT -p tcp --destination $primary --destination-port $port -j ACCEPT
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

link=enp8s0   # maybe "eth0" is needed here

# Tor
blacklist=tor-ddos
timeout=86400
seconds=300
hitcount=12   # both tries 1x per minute
connlimit=4   # 2 Tor relays at 1 ip address allowed

case $1 in
  start)  startFirewall ;;
  stop)   stopFirewall  ;;
esac
