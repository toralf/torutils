#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# implement a DDoS solution for a Tor relay for IPv4
# https://github.com/toralf/torutils

function addCommon() {
  # allow loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "DDoS IPv4 $(date -R)" -j ACCEPT

  # do not touch established connections
  $ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  $ipt -A INPUT -m conntrack --ctstate INVALID -j $jump

  # make sure NEW incoming tcp connections are SYN packets
  $ipt -A INPUT -p tcp ! --syn -m conntrack --ctstate NEW -j $jump

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.+\..+\..+\..+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"0.0.0.0/0"}; do
    $ipt -A INPUT -p tcp --dst $i --dport ${port:-22} -j ACCEPT
  done

  # manually filled from outsite
  __create_ipset $manuallist "hash:net timeout $((24 * 3600))"
  $ipt -A INPUT -m set --match-set $manuallist src -j $jump

  # PMTUD
  $ipt -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
  $ipt -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
  $ipt -A INPUT -p icmp --icmp-type parameter-problem -j ACCEPT

  # ping
  $ipt -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s --limit-burst 10 -j ACCEPT

  # DHCPv4
  $ipt -A INPUT -p udp --dport 68 -j ACCEPT

  # default policy
  $ipt -P INPUT $jump
}

function addTor() {

  # rule 1 (trust Tor authorities) is ORPort independend

  __create_ipset $trustlist "hash:ip maxelem 64"
  $ipt -A INPUT -p tcp -m set --match-set $trustlist src -j ACCEPT
  fill_trustlist &

  local netmask=${TORUTILS_NETMASK_V4:-32}
  local hashlimit_opts="--hashlimit-mode srcip,dstport --hashlimit-htable-max $max --hashlimit-htable-size $((max / 4)) --hashlimit-srcmask $netmask"
  local hashlimit_opts_2m="$hashlimit_opts --hashlimit-above 8/minute --hashlimit-burst 8 --hashlimit-htable-expire $((2 * 60 * 1000))"
  local hashlimit_opts_1h="$hashlimit_opts --hashlimit-above 16/hour --hashlimit-burst 16 --hashlimit-htable-expire $((60 * 60 * 1000))"

  # run over all <relay, orport> tupels
  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    # rule 2 (catch DDoS)

    local ddoslist="torutils-ddos-v4-$orport-$netmask"
    __create_ipset $ddoslist "hash:ip netmask $netmask maxelem $max timeout $((24 * 3600))"

    $common \
      -m hashlimit --hashlimit-name $ddoslist-2m $hashlimit_opts_2m \
      -j SET --add-set $ddoslist src --exist
    $common \
      -m hashlimit --hashlimit-name $ddoslist-1h $hashlimit_opts_1h \
      -j SET --add-set $ddoslist src --exist
    $common -m set --match-set $ddoslist src -j $jump

    # rule 3 (only 1 connection from each of up to 8 Tor relays per ip address)

    $common -m connlimit --connlimit-mask $netmask --connlimit-above 8 -j $jump

    # rule 4

    $common -j ACCEPT
  done
}

function relay_2_ip_and_port() {
  if [[ $relay =~ '[' || $relay =~ ']' || ! $relay =~ '.' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(tr ':' ' ' <<<$relay)
  if [[ -z $orip ]]; then
    echo " relay '$relay' has no valid ip" >&2
    return 1
  fi
  if [[ -z $orport ]]; then
    echo " relay '$relay' has no valid port" >&2
    return 1
  fi
}

function __create_ipset() {
  local name=${1?NAME NOT GIVEN}
  local cmd
  local family="inet"

  if ipset list -t $name &>/dev/null; then
    # is known
    cmd="ipset create -exist $name ${2?IPSET ARG NOT GIVEN} family $family"
    if $cmd 2>/dev/null; then
      return 0
    fi

    # but config changed, so create a tmp one, fill it and swap
    ipset destroy $name.tmp &>/dev/null || true
    cmd="ipset create $name.tmp ${2?IPSET ARG NOT GIVEN} family $family"
    if ! $cmd 2>/dev/null; then
      return 1
    fi
    {
      local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
      ipset save $name.tmp >$tmpfile
      ipset save $name | sed -e '1d' | sed -e "s, $name , $name.tmp ," -e 's,^add,add -exist,' >>$tmpfile
      xargs -r -L 1 echo "add -exist $name.tmp" <$tmpdir/$name >>$tmpfile
      ipset destroy $name.tmp &>/dev/null || true
      ipset restore <$tmpfile
      ipset swap $name $name.tmp
      ipset destroy $name.tmp
      rm $tmpfile
    } &
  else
    # create a new one, and if saved content was found then create a tmp one, fill it and swap
    cmd="ipset create $name ${2?IPSET ARG NOT GIVEN} family $family"
    if ! $cmd 2>/dev/null; then
      return 1
    fi
    if [[ -s $tmpdir/$name ]]; then
      {
        local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
        ipset save $name | sed -e "s, $name , $name.tmp ," -e 's,^add,add -exist,' >$tmpfile
        xargs -r -L 1 echo "add -exist $name.tmp" <$tmpdir/$name >>$tmpfile
        ipset destroy $name.tmp &>/dev/null || true
        ipset restore <$tmpfile
        ipset swap $name $name.tmp
        ipset destroy $name.tmp
        rm $tmpfile
      } &
    fi
  fi
}

function saveDdosIpsets() {
  [[ -d $tmpdir ]] || return 1

  iptables -nvL INPUT |
    grep 'match-set torutils-ddos-v' |
    awk '{ print $13 }' |
    while read -r name; do
      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
      if ipset list $name >$tmpfile; then
        if sed -i -e '1,8d' $tmpfile; then
          mv $tmpfile $tmpdir/$name
        fi
      fi
      rm -f $tmpfile
    done
}

function fill_trustlist() {
  (
    # snowflakes
    echo 141.212.118.18 193.187.88.42 193.187.88.43 193.187.88.44 193.187.88.45 193.187.88.46
    # Tor authorities
    echo 45.66.35.11 66.111.2.131 128.31.0.39 131.188.40.189 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118 216.218.219.41 217.196.147.77
    getent ahostsv4 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -uV
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a[0]' <<<$relays |
          sort -V
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function addServices() {
  local addr port service

  # local-address:local-port
  for service in ${TORUTILS_LOCAL_SERVICES_V4-}; do
    read -r addr port <<<$(tr ':' ' ' <<<$service)
    if [[ $addr == "0.0.0.0" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
  done

  # remote-address>local-port
  for service in ${TORUTILS_REMOTE_SERVICES_V4-}; do
    read -r addr port <<<$(tr '>' ' ' <<<$service)
    if [[ $addr == "0.0.0.0" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --src $addr --dport $port -j ACCEPT
  done
}

function addHetzner() {
  # detect Hetzner
  if ! host $(curl -4 --max-time 2 -s https://ip.hetzner.com) | grep -q -e 'your-server.de' -e 'hetzner'; then
    return
  fi

  local sysmon="torutils-hetznersysmon-v4"
  __create_ipset $sysmon "hash:ip maxelem 64"
  $ipt -A INPUT -m set --match-set $sysmon src -j ACCEPT
  {
    (
      echo 188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86
      getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
    ) |
      xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
}

function setSysctlValues() {
  if modinfo nf_conntrack &>/dev/null && ! lsmod | grep -q 'nf_conntrack'; then
    modprobe nf_conntrack
  fi

  sysctl -q -w net.netfilter.nf_conntrack_max=$max || sysctl -q -w net.nf_conntrack_max=$max
  sysctl -q -w net.ipv4.tcp_syncookies=1

  # make tcp_max_syn_backlog big enough to have ListenDrops being low or 0:
  # awk '(f==0) {i=1; while (i<=NF) {n[i] = $i; i++ }; f=1; next} (f==1){i=2; while (i<=NF) {printf "%s = %d\n", n[i], $i; i++}; f=0}' /proc/net/netstat | grep 'Drop'
  for i in net.netfilter.nf_conntrack_buckets net.ipv4.tcp_max_syn_backlog net.core.somaxconn; do
    if [[ $(sysctl -n $i) -lt $max ]]; then
      sysctl -q -w $i=$max
    fi
  done
}

function clearRules() {
  $ipt -P INPUT ACCEPT
  $ipt -F INPUT
  $ipt -Z INPUT
}

function printRuleStatistics() {
  date -R
  echo
  $ipt -nv -L INPUT
}

function getConfiguredRelays() {
  # shellcheck disable=SC2045 disable=SC2010
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null | grep -v -F -e '.sample' -e '.bak' -e '~' -e '@'); do
    if grep -q "^ServerTransportListenAddr " $f; then
      grep "^ServerTransportListenAddr " $f |
        awk '{ print $3 }' |
        grep -E "^([0-9]+\.){3}[0-9]+:[0-9]+$"
    else
      # OR port and address are defined either together in 1 line or in 2 different lines
      if orport=$(grep "^ORPort *" $f | grep -v -F -e ' NoListen' -e '[' -e ':auto' | grep -E "^ORPort[[:space:]]+.+[[:space:]]*"); then
        if grep -q -E "^ORPort[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+[[:space:]]*" <<<$orport; then
          awk '{ print $2 }' <<<$orport
        elif address=$(grep -E "^Address[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*" $f); then
          echo $(awk '{ print $2 }' <<<$address):$(awk '{ print $2 }' <<<$orport)
        fi
      fi
    fi
  done
}

function bailOut() {
  local rc=$?

  # sigpipe
  if [[ $rc -eq 141 ]]; then
    return 0
  fi

  trap - INT QUIT TERM EXIT
  echo -e "\n Something went wrong, stopping ...\n" >&2
  clearRules
  exit $rc
}

#######################################################################
set -eu # no -f
set -m  # allow fg in shell scripts
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066
trap '[[ $? -ne 0 ]] && echo "$0 $* unsuccessful" >&2' INT QUIT TERM EXIT
type curl ipset jq >/dev/null

manuallist="torutils-manual-v4" # to be filled manually from outside
trustlist="torutils-trust-v4"   # Tor authorities and snowflake servers
jobs=$((1 + $(nproc) / 4))      # parallel jobs of adding ips to an ipset
# hashes and ipsets are sized with respect to the available RAM in GiB
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ ${ram} -gt 8 ]]; then
  max=$((2 ** 22)) # 4M
elif [[ ${ram} -gt 1 ]]; then
  max=$((2 ** 20)) # 1M
else
  max=$((2 ** 18)) # 256K ca. 40 MiB RAM
fi
tmpdir=${TORUTILS_TMPDIR:-/var/tmp}

ipt="iptables"

action=${1-}
[[ $# -gt 0 ]] && shift
case $action in
start)
  setSysctlValues
  trap bailOut INT QUIT TERM EXIT
  clearRules
  jump=${TORUTILS_SAVE_RUN:-DROP}
  addCommon
  addHetzner
  addServices
  addTor ${*:-${TORUTILS_RELAYS_V4-$(getConfiguredRelays)}}
  trap - INT QUIT TERM EXIT
  ;;
stop)
  clearRules
  ;;
update)
  fill_trustlist
  ;;
test)
  ipset list -n >/dev/null
  TORUTILS_SAVE_RUN="ACCEPT" $0 start $*
  ;;
save)
  saveDdosIpsets
  ;;
*)
  printRuleStatistics
  ;;
esac

# wait till all bg jobs finished
while fg &>/dev/null; do
  :
done
