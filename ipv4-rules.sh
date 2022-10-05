#!/bin/bash
# set -x


function addCommon() {
  iptables -t raw -P PREROUTING ACCEPT     # drop explicitely
  iptables        -P INPUT      DROP       # accept explicitely
  iptables        -P OUTPUT     ACCEPT     # accept all

  # allow loopback
  iptables -A INPUT --in-interface lo -j ACCEPT -m comment --comment "$(date -R)"
  
  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  
  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  iptables -A INPUT -p tcp --dport ${port:-22} -j ACCEPT
  
  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


function __fill_lists()  {
  # dig +short snowflake-01.torproject.net. A
  # curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a[0]'
  echo 193.187.88.42 45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.34 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118 |
  xargs -r -n 1 -P 20 ipset add -exist $trustlist

  curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - |
  jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | sort | uniq -c | grep -v ' 1 ' |
  xargs -r -n 1 | grep -F '.' |
  xargs -r -n 1 -P 20 ipset add -exist $multilist
}


function addTor() {
  local blocklist=tor-ddos
  local multilist=tor-multi
  local trustlist=tor-trust

  ipset create -exist $blocklist hash:ip timeout 1800
  ipset create -exist $multilist hash:ip
  ipset create -exist $trustlist hash:ip

  __fill_lists & # lazy fill to minimize restart time

  #Establish the below iptables rules for each Tor relay (IP and port) combination defined in: 'relays="65.21.94.13:9001 65.21.94.13:443"'
  for relay in $relays
  do
    read -r orip orport <<< $(tr ':' ' ' <<< $relay)

    # Drop SYN flood packets when:
    # The initial 6 requests (--hashlimit-burst 6) are reached within 10 seconds (--hashlimit-above 6/minute).
    # Further, drop all requests and only allow one request to be accepted per each following 10 second period (--hashlimit-above 6/minute).
    # If no further requests have been made and  ~16 hours (--hashlimit-htable-expire 60000) have passed, then reset the counts to 0 and allow all traffic. Another words, maintain packet counts for ~16 hours before seeing no traffic and reseting the counters to 0 and allowing all traffic.
    # For more information, decent tutorial: https://poorlydocumented.com/2017/08/understanding-iptables-hashlimit-module/ 
    iptables -t raw -A PREROUTING -p tcp --dst $orip --dport $orport --syn -m hashlimit --hashlimit-name $blocklist --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-above 6/minute --hashlimit-burst 6 --hashlimit-htable-expire 60000 -j SET --add-set $blocklist src --exist
    iptables -t raw -A PREROUTING -p tcp -m set --match-set $blocklist src -j DROP

    # Accept all traffic for the Tor authorities set in $trustlist
    iptables -A INPUT -p tcp --dst $orip --dport $orport -m set --match-set $trustlist src -j ACCEPT

    # Drop connections when they exceed more than 3 concurrent connections (--connlimit-above 3) per IP address (--connlimit-mask 32)
    iptables -A INPUT -p tcp --dst $orip --dport $orport -m connlimit --connlimit-mask 32 --connlimit-above 3 -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp -m set --match-set $blocklist src -j DROP
  
    # Drop connection attempts per IP (--connlimit-mask 32) when they exceed more than 1 concurrent connection (--connlimit-above 1) and are NOT on the list of 2 Tor relays per IP ($multiset)
    # OR Drop connection attemps per IP (--connlimit-mask 32) when they exceed more than 2 concurrent connections 
    iptables -A INPUT -p tcp --dst $orip --dport $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 1 -m set ! --match-set $multilist src -j DROP
    iptables -A INPUT -p tcp --dst $orip --dport $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP
  
    # Accept remaining connections
    iptables -A INPUT -p tcp --dst $orip --dport $orport -j ACCEPT
  done

  # Accept already established connections
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate INVALID             -j DROP
}


# Comment out when not a Hetzner customers: https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
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


# only valid for zwiebeltoralf.de
function addMisc() {
  local addr=$(ip -4 address | awk ' /inet .* scope global enp8s0/ { print $2 }' | cut -f1 -d'/')
  local port

  port=$(crontab -l -u torproject | grep -m 1 -Po "\-\-port \d+" | cut -f2 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
  port=$(crontab -l -u tinderbox  | grep -m 1 -Po "\-\-port \d+" | cut -f2 -d ' ')
  [[ -n "$port" ]] && iptables -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
}


function clearAll() {
  iptables -P INPUT   ACCEPT

  for table in filter raw
  do
    iptables -F -t $table
    iptables -X -t $table
    iptables -Z -t $table
  done
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor, this should match ORPort, see https://github.com/toralf/torutils/issues/1
relays="65.21.94.13:9001 65.21.94.13:443"

case $1 in
  start)  addCommon
          addTor
          addHetzner
          addMisc
          ;;
  stop)   clearAll
          ;;
  *)      iptables -nv -L -t raw || echo -e "\n\n+ + + Warning: you kernel lacks CONFIG_IP_NF_RAW=y\n\n"
          echo
          iptables -nv -L
          ;;
esac

