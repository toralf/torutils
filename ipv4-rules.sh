#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


function addCommon() {
  iptables -P INPUT  ${DEFAULT_POLICY_INPUT:-DROP}
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


function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name hash:ip family inet ${2:-}"

  if ! $cmd 2>/dev/null; then
    if ! (ipset list -t $name &>/dev/null && saveIpset $name && ipset destroy $name && $cmd); then
      return 1
    fi
  fi
}


function __fill_trustlist() {
  (
    echo "193.187.88.42 193.187.88.43 193.187.88.44 193.187.88.45 193.187.88.46 141.212.118.18"
    echo "45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.39 131.188.40.189 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118"

    getent ahostsv4 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }'
    curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a[0]'
  ) |
  xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}


function __fill_multilist() {
  (
    if [[ -s /var/tmp/$multilist ]]; then
      cat /var/tmp/$multilist
    fi
    curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - |
    jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | awk '{ print $1 }' | sort | uniq -d |
    tee /var/tmp/$multilist.new
    if [[ -s /var/tmp/$multilist.new ]]; then
      mv /var/tmp/$multilist.new /var/tmp/$multilist
    fi
  ) |
  xargs -r -n 1 -P $jobs ipset add -exist $multilist
}


function __fill_ddoslist() {
  if [[ -f /var/tmp/$ddoslist ]]; then
    cat /var/tmp/$ddoslist |
    xargs -r -n 3 -P $jobs ipset add -exist $ddoslist
    rm /var/tmp/$ddoslist
  fi
}


function addTor() {
  __create_ipset $trustlist
  __fill_trustlist &
  __create_ipset $multilist
  __fill_multilist &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask 32 --hashlimit-htable-size $(( 2**18 )) --hashlimit-htable-max $(( 2**18 ))"
  for relay in $*
  do
    if [[ $relay =~ '[' || $relay =~ ']' || ! $relay =~ '.' || ! $relay =~ ':' ]]; then
      echo " relay '$relay' cannot be parsed" >&2
      return 1
    fi
    read -r orip orport <<< $(tr ':' ' ' <<< $relay)
    local synpacket="iptables -A INPUT -p tcp --dst $orip --dport $orport --syn"

    local ddoslist="tor-ddos-$orport"     # this holds ips classified as DDoS'ing the local OR port
    __create_ipset $ddoslist "timeout $(( 24*3600 )) maxelem $(( 2**18 ))"
    __fill_ddoslist &

    # rule 1
    $synpacket -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    $synpacket -m set --match-set $multilist src -m connlimit --connlimit-mask 32 --connlimit-upto 4 -j ACCEPT

    # rule 3
    $synpacket $hashlimit --hashlimit-name tor-ddos-$orport --hashlimit-above 6/minute --hashlimit-burst 5 --hashlimit-htable-expire $(( 2*60*1000 )) -j SET --add-set $ddoslist src --exist
    $synpacket -m set --match-set $ddoslist src -j DROP

    # rule 4
    $synpacket -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP

    # rule 5
    $synpacket $hashlimit --hashlimit-name tor-rate-$orport --hashlimit-above 1/hour --hashlimit-burst 1 --hashlimit-htable-expire $(( 2*60*1000 )) -j DROP

    # rule 6
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

  __create_ipset $sysmon
  {
    (
      getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }'
      echo "188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86"
    ) | sort -u |
    xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
  iptables -A INPUT -m set --match-set $sysmon src -j ACCEPT
}


function setSysctlValues() {
  sysctl -w net.ipv4.tcp_syncookies=1
  sysctl -w net.netfilter.nf_conntrack_buckets=$(( 2**18 ))
  sysctl -w net.netfilter.nf_conntrack_max=$(( 2**18 ))

  # make it big enough to have ListenDrops being 0 (zero):
  # cat /proc/net/netstat | awk '(f==0) {i=1; while (i<=NF) {n[i] = $i; i++ }; f=1; next} (f==1){i=2; while (i<=NF) {printf "%s = %d\n", n[i], $i; i++}; f=0}' | grep 'Drop'
  sysctl -w net.ipv4.tcp_max_syn_backlog=$(( 2**18 ))
  sysctl -w net.core.somaxconn=$(( 2**18 ))
}


function clearRules() {
  iptables -P INPUT  ACCEPT
  iptables -P OUTPUT ACCEPT

  iptables -F
  iptables -X
  iptables -Z
}


function printRuleStatistics()  {
  date -R
  echo
  iptables -nv -L INPUT
}


function getConfiguredRelays()  {
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null)
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

  echo -e "\n Something went wrong, stopping ...\n" >&2
  clearRules
  exit 1
}


function saveIpset() {
  local name=$1

  ipset list $name | sed -e '1,8d' > /var/tmp/$name.new
  mv /var/tmp/$name.new /var/tmp/$name
}


function saveAllIpsets() {
  ipset list -t | grep "^Name: tor-ddos-" | awk '{ print $2 }' |
  while read name
  do
    saveIpset $name
  done
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

trustlist="tor-trust"     # Tor authorities and snowflake
multilist="tor-multi"     # Tor relay ip addresses hosting > 1 relays
jobs=$(( 1+$(nproc)/2 ))

trap bailOut INT QUIT TERM EXIT
action=${1:-}
shift || true
case $action in
  start)  clearRules
          setSysctlValues 1>/dev/null || echo "couldn't set sysctl values" >&2
          addCommon
          addHetzner
          addLocalServices
          addTor ${*:-${CONFIGURED_RELAYS:-$(getConfiguredRelays)}}
          ;;
  stop)   clearRules
          saveAllIpsets
          ;;
  save)   saveAllIpsets
          ;;
  update) __fill_trustlist
          __fill_multilist
          ;;
  *)      printRuleStatistics
          ;;
esac
trap - INT QUIT TERM EXIT
