#!/bin/bash
# set -x


function init() {
  # iptables
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP
  
  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  
  # allow local traffic
  iptables -A INPUT --in-interface lo -j ACCEPT -m comment --comment "$(date -R)"
  
  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --destination-port ${port:-22} -j ACCEPT
  
  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


function addTor() {
  local blocklist=tor-ddos

  ipset create -exist $blocklist hash:ip timeout 1800

  for relay in $relays
  do
    local oraddr=$(sed -e 's,:[0-9]*$,,' <<< $relay)
    local orport=$(grep -Po '\d+$' <<< $relay)
    local name=$blocklist-$orport

    # add to blocklist if appropriate
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m hashlimit --hashlimit-name $name --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-above 10/minute --hashlimit-htable-expire 60000 -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 32 --connlimit-above 10 -j SET --add-set $blocklist src --exist

    # drop blocklisted
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $blocklist src -j DROP
    
    # handle buggy (?) clients
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP
    
    # allow remaining
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done

  # allow already established connections
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate INVALID             -j DROP
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


# local stuff only
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
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
relays="65.21.94.13:443   65.21.94.13:9001"

case $1 in
  start)  init
          addHetzner
          addTor
          addLocal
          ;;
  stop)   clearAll
          ;;
esac

