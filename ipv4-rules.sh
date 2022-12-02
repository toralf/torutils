#!/bin/bash
# set -x


function addCommon() {
  iptables -P INPUT  DROP
  iptables -P OUTPUT ACCEPT

  # allow loopback
  iptables -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

  # do not touch established connections
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config | awk '{ print $2 }')
  local addr=$(grep -m 1 -E "^ListenAddress\s+.+$"  /etc/ssh/sshd_config | awk '{ print $2 }' | grep -F '.')
  iptables -A INPUT -p tcp --dst ${addr:-"0.0.0.0/0"} --dport ${port:-22} -j ACCEPT

  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


function __fill_trustlist() {
  (
    echo "193.187.88.42 45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.39 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118"
    getent ahostsv4 snowflake-01.torproject.net. | awk '{ print $1 }' | sort -u | xargs
    if jq --help &>/dev/null; then
      curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a[0]' | sort -u
    else
      { echo "please install package jq to fetch the latest Tor authority ips" >&2 ; }
    fi
  ) | xargs -r -n 1 -P 20 ipset add -exist $trustlist
}


function __create_ipset() {
  local name=$1
  local minutes=$2

  local cmd="ipset create -exist $name hash:ip family inet timeout $(( minutes*60 )) maxelem $(( 2**20 ))"
  if ! $cmd 2>/dev/null; then
    ipset destroy $name
    $cmd
  fi
}


function addTor() {
  local trustlist="tor-trust"
  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask 32 --hashlimit-htable-size $(( 2**20 )) --hashlimit-htable-max $(( 2**20 ))"

  ipset create -exist $trustlist hash:ip family inet
  __fill_trustlist &

  for relay in $*
  do
    read -r orip orport <<< $(tr ':' ' ' <<< $relay)

    local ddoslist="tor-ddos-$orport"
    local connlist="tor-conn-$orport"

    __create_ipset $ddoslist "30"
    __create_ipset $connlist "2*24*60"

    local synpacket="iptables -A INPUT -p tcp --dst $orip --dport $orport --syn"

    # rule 1
    $synpacket -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    $synpacket $hashlimit --hashlimit-htable-expire $(( 60*1000 )) --hashlimit-name tor-ddos-$orport --hashlimit-above 6/minute --hashlimit-burst 5 -j SET --add-set $ddoslist src --exist
    $synpacket -m set --match-set $ddoslist src -j SET --add-set $connlist src --exist
    $synpacket -m set --match-set $ddoslist src -j DROP

    # rule 3
    $synpacket $hashlimit --hashlimit-htable-expire $(( 60*1000 )) --hashlimit-name tor-limit-$orport --hashlimit-above 1/minute --hashlimit-burst 1 -j DROP

    # rule 4
    $synpacket -m connlimit --connlimit-mask 32 --connlimit-above 2                                  -j DROP
    $synpacket -m connlimit --connlimit-mask 32 --connlimit-above 0 -m set --match-set $connlist src -j DROP

    # rule 5
    $synpacket -j ACCEPT
  done
}


function addLocalServices() {
  local addr
  local port

  for service in ${ADD_LOCAL_SERVICES:-}
  do
    read -r addr port <<< $(tr ':' ' ' <<< $service)
    if [[ $addr = "0.0.0.0" ]]; then
      addr+="/0"
    fi
    iptables -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
  done
}


function addHetzner() {
  local sysmon="hetzner-sysmon"

  ipset create -exist $sysmon hash:ip family inet
  iptables -A INPUT -m set --match-set $sysmon src -j ACCEPT
  {
    (
      getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
      echo "188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86"
    ) | xargs -r -n 1 -P 20 ipset add -exist $sysmon
  } &
}


function clearAll() {
  iptables -P INPUT  ACCEPT
  iptables -P OUTPUT ACCEPT

  iptables -F
  iptables -X
  iptables -Z
}


function printFirewall()  {
  date -R
  echo
  iptables -nv -L INPUT
}


function getConfiguredRelays()  {
  for f in /etc/tor/torrc*
  do
    if orport=$(grep "^ORPort *" $f | grep -v -F -e ' NoListen' -e '[' | grep -P "^ORPort\s+.+\s*"); then
      if grep -q -Po "^ORPort\s+\d+\.\d+\.\d+\.\d+\:\d+\s*" <<< $orport; then
        awk '{ print $2 }' <<< $orport
      else
        if address=$(grep -P "^Address\s+\d+\.\d+\.\d+\.\d+\s*" $f); then
          echo $(awk '{ print $2 }' <<< $address):$(awk '{ print $2 }' <<< $orport)
        fi
      fi
    fi
  done
}


function bailOut()  {
  trap - INT QUIT TERM EXIT

  echo "Something went wrong, stopping ..."
  clearAll
  exit 1
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

trap bailOut INT QUIT TERM EXIT
case ${1:-} in
  start)  clearAll
          addCommon
          addHetzner
          addLocalServices
          addTor ${CONFIGURED_RELAYS:-$(getConfiguredRelays)}
          ;;
  stop)   clearAll
          ipset list -t | grep -P "^Name: tor-(conn|ddos)-\d+$" | cut -f2 -d' ' | xargs -r -n 1 ipset flush 2>/dev/null
          ;;
  *)      printFirewall
          ;;
esac
trap - INT QUIT TERM EXIT
