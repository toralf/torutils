#!/bin/bash
# set -x


function addTor() {
  # ipset for blocked ip addresses
  if [[ -s /var/tmp/ipset.$blocklist ]]; then
    ipset restore -exist -f /var/tmp/ipset.$blocklist && shred -u /var/tmp/ipset.$blocklist
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
  
  # the ruleset for inbound to an ORPort
  for orport in ${orports[*]}
  do
    # add an ip to the blocklist if ...
    # ... another packet arrived within timeout
    # ... there're 2 connections and another SYN is made
    # ... there're more than 2 connections already
    iptables -A INPUT -p tcp         --destination $oraddr --destination-port $orport -m set --match-set $blocklist src                    -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp   --syn --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 32 --connlimit-above 2 -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp ! --syn --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 32 --connlimit-above 2 -j SET --add-set $blocklist src --exist

    # drop all packets from blocklist entries
    iptables -A INPUT -p tcp -m set --match-set $blocklist src -j DROP
    # allow to connect
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done

  # trust already established connections - this is almost Tor traffic outbound to an ORPort
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

