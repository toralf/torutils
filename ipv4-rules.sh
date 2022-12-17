#!/bin/bash
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


function __fill_trustlist() {
  (
    echo "193.187.88.42 193.187.88.43 193.187.88.44 193.187.88.45 193.187.88.46 141.212.118.18"
    echo "45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.39 131.188.40.189 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118"

    getent ahostsv4 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }'
    if jq --help &>/dev/null; then
      curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a[0]'
    else
      echo " please install package jq to fetch the latest Tor authority ips" >&2
    fi
  ) | sort -u |
  xargs -r -n 1 -P $(nproc) ipset add -exist $trustlist
}


function __create_ipset() {
  local name=$1
  local cmd="ipset create -exist $name hash:ip family inet ${2:-}"

  if ! $cmd 2>/dev/null; then
    local content=$(ipset list $name | sed -e '1,8d')
    if ! ipset destroy $name; then
      echo " ipset does not work, cannot continue" >&2
      exit 1
    fi
    $cmd
    { echo $content | xargs -r -n 3 -P $(nproc) ipset add -exist $name ; } &
  fi
}


function addTor() {
  local trustlist="tor-trust"
  __create_ipset $trustlist
  __fill_trustlist &

  local hashlimit="-m hashlimit --hashlimit-mode srcip,dstport --hashlimit-srcmask 32 --hashlimit-htable-size $(( 2**20 )) --hashlimit-htable-max $(( 2**20 ))"
  for relay in $*
  do
    read -r orip orport <<< $(tr ':' ' ' <<< $relay)

    local synpacket="iptables -A INPUT -p tcp --dst $orip --dport $orport --syn"
    local ddoslist="tor-ddos-$orport"
    __create_ipset $ddoslist "timeout $(( 24*60*60 )) maxelem $(( 2**20 ))"
    if [[ -f /var/tmp/$ddoslist ]]; then
      { cat /var/tmp/$ddoslist | xargs -r -n 3 -P $(nproc) ipset add -exist $ddoslist && rm /var/tmp/$ddoslist ; } &
    fi

    # rule 1
    $synpacket -m set --match-set $trustlist src -j ACCEPT

    # rule 2
    $synpacket $hashlimit --hashlimit-htable-expire $(( 24*60*60*1000 )) --hashlimit-name tor-ddos-$orport --hashlimit-above 6/minute --hashlimit-burst 5 -j SET --add-set $ddoslist src --exist
    $synpacket -m set --match-set $ddoslist src -j DROP

    # rule 3
    $synpacket $hashlimit --hashlimit-htable-expire $(( 120*1000 )) --hashlimit-name tor-rate-$orport --hashlimit-above 1/hour --hashlimit-burst 1 -j DROP

    # rule 4
    $synpacket -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP

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

  __create_ipset $sysmon
  {
    (
      getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }'
      echo "188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86"
    ) | sort -u |
    xargs -r -n 1 -P $(nproc) ipset add -exist $sysmon
  } &
  iptables -A INPUT -m set --match-set $sysmon src -j ACCEPT
}


function setSysctlValues() {
  sysctl -w net.ipv4.tcp_syncookies=1
  sysctl -w net.netfilter.nf_conntrack_buckets=$(( 2**21 ))
  sysctl -w net.netfilter.nf_conntrack_max=$(( 2**21 ))
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

  echo "Something went wrong, stopping ..." >&2
  clearAll
  exit 1
}


function saveIpsets() {
  ipset list -t | grep "^Name: tor-ddos-" | awk '{ print $2 }' |
  while read name
  do
    ipset list $name | sed -e '1,8d' > /var/tmp/$name
  done
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
          setSysctlValues 1>/dev/null || echo "couldn't set sysctl values" >&2
          ;;
  stop)   clearAll
          saveIpsets
          ;;
  *)      printFirewall
          ;;
esac
trap - INT QUIT TERM EXIT
