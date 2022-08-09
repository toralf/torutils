#!/bin/bash
# set -x


function addTor() {
  # ipset for Tor authorities https://metrics.torproject.org/rs.html#search/flag:authority%20
  local authlist=tor-authorities

  ipset create -exist $authlist hash:ip
  for i in 128.31.0.34 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 194.13.81.26 199.58.81.140 204.13.164.118 45.66.33.45 66.111.2.131 86.59.21.38
  do
    ipset add -exist $authlist $i
  done

  # ipset for blocked ip addresses
  if [[ -s /var/tmp/ipset.$blocklist ]]; then
    ipset restore -exist -f /var/tmp/ipset.$blocklist
  else
    ipset create -exist $blocklist hash:ip timeout 1800
  fi

  # iptables
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP
  
  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP -m comment --comment "$(date)"
  
  # allow local traffic
  iptables -A INPUT --in-interface lo -j ACCEPT
  
  # the ruleset for an orport
  for orport in ${orports[*]}
  do
    # trust Tor authorities
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $authlist src -j ACCEPT
    # penalty if a 3rd connection is tried to open
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 1 -j SET --add-set $blocklist src --exist
  done

  # drop traffic from blocklist to ORPort
  iptables -A INPUT -p tcp --destination $oraddr -m multiport --destination-ports $(tr ' ' ',' <<< ${orports[*]}) -m set --match-set $blocklist src -j DROP

  # allow to connect to ORport
  for orport in ${orports[*]}
  do
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done
  
  # trust already established connections - this is almost Tor traffic initiated by us
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate INVALID             -j DROP

  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --destination-port ${port:-22} -j ACCEPT
  
  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


# only needed for Hetzner customers
# https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
function addHetzner() {
  local monlist=hetzner-monlist

  ipset create -exist $monlist hash:ip
  getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u |\
  while read i
  do
    ipset add -exist $monlist $i
  done
  iptables -A INPUT -m set --match-set $monlist src -j ACCEPT
}


# replace this content with your own stuff -or- kick it off
function addLocal() {
  local addr=$(ip -4 address | grep -w "inet .* scope global enp8s0" | awk '{ print $2 }' | cut -f1 -d'/')
  local port

  port=$(crontab -l -u torproject | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --destination $addr --destination-port $port -j ACCEPT
  port=$(crontab -l -u tinderbox  | grep -m 1 -F " --port" | sed -e 's,.* --port ,,g' | cut -f1 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --destination $addr --destination-port $port -j ACCEPT
}


function clearAll() {
  iptables -F
  iptables -X
  iptables -Z

  iptables -P INPUT   ACCEPT
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD ACCEPT

  ipset save $blocklist -f /var/tmp/ipset.$blocklist.tmp &&\
  mv /var/tmp/ipset.$blocklist.tmp /var/tmp/ipset.$blocklist &&\
  ipset destroy $blocklist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="65.21.94.13"
orports=(443 9001)

blocklist=tor-ddos

case $1 in
  start)  addTor
          addHetzner
          addLocal
          ;;
  stop)   clearAll
          ;;
esac

