#!/bin/bash
# set -x


function addCommon() {
  # iptables
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP

  # allow loopback
  iptables -A INPUT --in-interface lo -j ACCEPT -m comment --comment "$(date -R)"
  
  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  
  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --destination-port ${port:-22} -j ACCEPT
  
  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


function __fill_list()  {
  # central Tor services
  #dig +short snowflake-01.torproject.net. A
  #curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a[0]'
  echo 193.187.88.42 45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.34 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118 |
  xargs -r -n 1 -P 20 ipset add -exist $trustlist
}


function addTor() {
  local blocklist=tor-ddos
  local trustlist=tor-trust

  ipset create -exist $blocklist hash:ip timeout 1800
  ipset create -exist $trustlist hash:ip

  __fill_list & # helpful but not mandatory -> background to close a race gap

  for relay in $relays
  do
    local oraddr=$(sed -e 's,:[0-9]*$,,' <<< $relay)
    local orport=$(grep -Po '\d+$' <<< $relay)

    # allow trusted
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $trustlist src -j ACCEPT

    # blocklist rules
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m hashlimit --hashlimit-name $blocklist --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-above 8/minute --hashlimit-burst 6 --hashlimit-htable-expire 60000 -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 32 --connlimit-above 3 -j SET --add-set $blocklist src --exist

    # drop blocklisted entirely
    iptables -A INPUT -p tcp -m set --match-set $blocklist src -j DROP
  
    # handle buggy (?) clients
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP
  
    # allow remaining
    iptables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done

  # allow already established connections
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate INVALID             -j DROP
}


# only useful for Hetzner customers: https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
function addHetzner() {
  local monlist=hetzner-monlist

  ipset create -exist $monlist hash:ip

  # getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u | xargs
  for i in 188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86
  do
    ipset add -exist $monlist $i
  done
  iptables -A INPUT -m set --match-set $monlist src -j ACCEPT
}


# make 2 local status pages available
function addMisc() {
  local addr=$(ip -4 address | awk ' /inet .* scope global enp8s0/ { print $2 }' | cut -f1 -d'/')
  local port

  port=$(crontab -l -u torproject | grep -m 1 -Po "\-\-port \d+" | cut -f2 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --destination $addr --destination-port $port -j ACCEPT
  port=$(crontab -l -u tinderbox  | grep -m 1 -Po "\-\-port \d+" | cut -f2 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --destination $addr --destination-port $port -j ACCEPT
}


function clearAll() {
  iptables -P INPUT   ACCEPT
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD ACCEPT
  
  iptables -F
  iptables -X
  iptables -Z
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor, this must match ORPort
relays="65.21.94.13:9001   65.21.94.13:443"

case $1 in
  start)  addCommon
          addHetzner
          addTor
          addMisc
          ;;
  stop)   clearAll
          ;;
     *)   exit 1
          ;;
esac

