#!/bin/bash
# set -x


function addTor() {
  iptables -P INPUT   DROP
  iptables -P OUTPUT  ACCEPT
  iptables -P FORWARD DROP
  
  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP -m comment --comment "$(date)"
  
  # allow local traffic
  iptables -A INPUT --in-interface lo -j ACCEPT
  
  # create authlist for Tor authorities
  local authlist=tor-authorities
  ipset create -exist $authlist hash:ip
  # https://metrics.torproject.org/rs.html#search/flag:authority%20
  for i in 128.31.0.34 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 194.13.81.26 199.58.81.140 204.13.164.118 45.66.33.45 66.111.2.131 86.59.21.38
  do
    ipset add -exist $authlist $i
  done

  # create denylist for ip addresses
  if [[ -s /var/tmp/ipset.$denylist ]]; then
    ipset restore -exist -f /var/tmp/ipset.$denylist
  else
    ipset create -exist $denylist hash:ip timeout 1800
  fi

  # the ruleset for an orport
  for orport in ${orports[*]}
  do
    # <= 11 new connection attempts within 5 min
    local name=$denylist-$orport
    iptables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m recent --name $name --set
    iptables -A INPUT -p tcp --syn --destination $oraddr --destination-port $orport -m recent --name $name --update --seconds 300 --hitcount 11 --rttl -j SET --add-set $denylist src --exist
    # trust Tor authorities
    iptables -A INPUT -p tcp       --destination $oraddr --destination-port $orport -m set --match-set $authlist src -j ACCEPT
    # <=2 connections
  iptables -A INPUT -p tcp         --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 128 --connlimit-above 2 -j SET --add-set $denylist src --exist
  done

  # drop any traffic from denylist
  iptables -A INPUT -p tcp -m set --match-set $denylist src -j DROP
  
  # allow passing packets to connect to ORport
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

  ipset save $denylist -f /var/tmp/ipset.$denylist.tmp &&\
  mv /var/tmp/ipset.$denylist.tmp /var/tmp/ipset.$denylist &&\
  ipset destroy $denylist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="65.21.94.13"
orports=(443 9001)

denylist=tor-ddos

case $1 in
  start)  addTor
          addHetzner
          addLocal
          ;;
  stop)   clearAll
          ;;
esac

# the module is loaded/intialized by its first usage
if ! grep -q "10000" /sys/module/xt_recent/parameters/ip_list_tot; then
  cat << EOF -
  The parameter 'ip_list_tot' of kernel module 'xt_recent' is not set to its max value."
  Put either a line into /etc/modprobe.d/xt_recent.conf like:
      options xt_recent ip_list_tot=10000
  or add to the kernel command line (into the grub config file) the string
      xt_recent.ip_list_tot=10000
EOF
fi

