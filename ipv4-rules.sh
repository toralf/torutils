#!/bin/bash
# set -x


function addTor() {
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP
  
  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP -m comment --comment "$(date)"
  
  # local traffic
  iptables -A INPUT --in-interface lo --source 127.0.0.1/8 --destination 127.0.0.1/8 -j ACCEPT
  
  # create allowlist for Tor authorities
  allowlist=tor-authorities
  ipset create -exist $allowlist hash:ip
  # get-authority-ips.sh | grep -F '.' | xargs
  for i in 128.31.0.34 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 194.13.81.26 199.58.81.140 204.13.164.118 45.66.33.45 66.111.2.131 86.59.21.38
  do
    ipset add -exist $allowlist $i
  done

  # create denylist for ip addresses violating ratelimit/connlimit rules for incoming NEW Tor connections
  if [[ -s /var/tmp/ipset.$denylist ]]; then
    ipset restore -exist -f /var/tmp/ipset.$denylist
  else
    ipset create -exist $denylist hash:ip timeout $timeout
  fi
  if [[ ! $(cat /sys/module/*/parameters/ip_list_tot) = "10000" ]]; then
    echo " consider to increase the ip_list_tot parameter"
  fi
  for orport in 443 9001
  do
    name=$denylist-$orport
    iptables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m recent --name $name --set
    iptables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m recent --name $name --update --seconds $seconds --hitcount $hitcount --rttl -j SET --add-set $denylist src
    iptables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 32 --connlimit-above $connlimit -j SET --add-set $denylist src
  done
 
  # accept Tor authorities traffic to relay address, drop traffic of denylist members entirely, allow remaining to ORport
  iptables -A INPUT -p tcp --destination $oraddr -m set --match-set $allowlist src -j ACCEPT
  iptables -A INPUT -p tcp -m set --match-set $denylist src -j DROP
  for orport in 443 9001
  do
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done
  
  # trust already established connections - this is almost Tor traffic initiated by us
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate INVALID             -j DROP

  # ssh
  sshport=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --destination $sshaddr --destination-port ${sshport:-22} -j ACCEPT
  
  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


function addMisc() {
  # https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
  monlist=hetzner-monlist
  ipset create -exist $monlist hash:ip
  getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u |\
  while read i
  do
    ipset add -exist $monlist $i
  done
  iptables -A INPUT -m set --match-set $monlist src -j ACCEPT

  # local stuff
  port=$(crontab -l -u torproject | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --destination $sshaddr --destination-port $port -j ACCEPT
  port=$(crontab -l -u tinderbox  | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --destination $sshaddr --destination-port $port -j ACCEPT
}


function clearAll() {
  iptables -F
  iptables -X
  iptables -Z

  iptables -P INPUT   ACCEPT
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD ACCEPT

  ipset save $denylist -f /var/tmp/ipset.$denylist.tmp && mv /var/tmp/ipset.$denylist.tmp /var/tmp/ipset.$denylist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="65.21.94.13"
denylist=tor-ddos
timeout=86400
seconds=300
hitcount=12   # both tries 1x per minute and maybe a tor client is running there too
connlimit=4   # 2 Tor relays at 1 ip address

# if there're 2 ip addresses then do assume that the 2nd is used for ssh etc.
dev=$(ip -4 route | grep "^default" | awk '{ print $5 }')
sshaddr=$(ip -4 address show dev $dev | grep -w "inet .* scope global" | grep -v -w "$oraddr" | awk '{ print $2 }' | cut -f1 -d'/')
if [[ -z $sshaddr ]]; then
  sshaddr=$oraddr
fi

case $1 in
  start)  addTor
          addMisc   # local stuff
          ;;
  stop)   clearAll
          ;;
esac
