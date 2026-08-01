#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# implement a DDoS solution for a Tor relay for IPv6
# https://github.com/toralf/torutils

function addCommon() {
  # loopback
  $ipt -A INPUT --in-interface lo -m comment --comment "DDoS IPv6 $(date -R)" -j ACCEPT

  # do not touch established connections
  $ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  $ipt -A INPUT -m conntrack --ctstate INVALID -j $jump

  # make sure NEW incoming tcp connections are SYN packets
  $ipt -A INPUT -p tcp ! --syn -m conntrack --ctstate NEW -j $jump

  # ssh
  local addr=$(grep -E "^ListenAddress\s+.*:.*:.*$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{ print $2 }')
  for i in ${addr:-"::/0"}; do
    $ipt -A INPUT -p tcp --dst $i --dport ${port:-22} -j ACCEPT
  done

  # manually filled from outsite
  __create_ipset $manuallist "hash:net timeout $((24 * 3600))"
  $ipt -A INPUT -m set --match-set $manuallist src -j $jump

  # see RFC 4890

  # IPv6 Path MTU Discovery
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type time-exceeded -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type parameter-problem -j ACCEPT

  # Neighbor Discovery Protocol - prevent Remote-Spoofing
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -m hl --hl-eq 255 -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -m hl --hl-eq 255 -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j ACCEPT
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j ACCEPT

  # ping
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s --limit-burst 10 -j ACCEPT

  # not at a server
  $ipt -A INPUT -p ipv6-icmp --icmpv6-type redirect -j $jump

  # DHCPv6
  $ipt -A INPUT -p udp --dport 546 -j ACCEPT

  # IPv6 Multicast
  $ipt -A INPUT -p udp --source fe80::/10 --dst ff02::/80 -j ACCEPT

  # default policy
  $ipt -P INPUT $jump
}

function addTor() {

  # rule 1 (trust Tor authorities) is ORPort independend

  __create_ipset $trustlist "hash:ip maxelem 64"
  $ipt -A INPUT -p tcp -m set --match-set $trustlist src -j ACCEPT
  fill_trustlist &

  # provider who usually do provide a /64 netmask for each system
  __create_ipset $hosterlist "hash:net maxelem 64"
  fill_hosterlist &

  local netmask=${TORUTILS_NETMASK_V6:-128}
  local hashlimit_opts="--hashlimit-mode srcip,dstport --hashlimit-htable-max $max --hashlimit-htable-size $((max / 4))"
  local hashlimit_opts_2m="$hashlimit_opts --hashlimit-above 8/minute --hashlimit-burst 8 --hashlimit-htable-expire $((2 * 60 * 1000))"
  local hashlimit_opts_1h="$hashlimit_opts --hashlimit-above 16/hour --hashlimit-burst 16 --hashlimit-htable-expire $((60 * 60 * 1000))"

  # run over all <relay, orport> tupels
  for relay in $(xargs -n 1 <<<$* | awk '{ if (x[$1]++) print "duplicate", $1 >"/dev/stderr"; else print $1 }'); do
    relay_2_ip_and_port
    local common="$ipt -A INPUT -p tcp --dst $orip --dport $orport"

    # rule 2 (catch DDoS)

    # default netmask
    local ddoslist="torutils-ddos-v6-$orport-$netmask"
    __create_ipset $ddoslist "hash:ip netmask $netmask maxelem $max timeout 86400"

    # avoid overflow attacks, if netmask is bigger than /64
    #   - the hosterlist items are collected from providers where attacks were observed
    #   - regular check the default ipset for possible updates for the hosterlist:
    #       awk '{ print $1 }' /var/tmp/torutils-ddos-v6-* | sort -V | uniq -c | less
    #     and watch the /128 hashes too:
    #       cut -f 2 -d ' ' /proc/net/ip6t_hashlimit/torutils-ddos-v6-* | cut -f 1 -d '-' | sort -V | uniq -c | less

    if [[ $netmask -gt 64 ]]; then
      local ddoslist64="torutils-ddos-v6-$orport-64"
      __create_ipset $ddoslist64 "hash:ip netmask 64 maxelem $max timeout 86400"

      $common -m set --match-set $hosterlist src \
        -m hashlimit --hashlimit-name $ddoslist64-2m $hashlimit_opts_2m --hashlimit-srcmask 64 \
        -j SET --add-set $ddoslist64 src --exist
      $common -m set --match-set $hosterlist src \
        -m hashlimit --hashlimit-name $ddoslist64-1h $hashlimit_opts_1h --hashlimit-srcmask 64 \
        -j SET --add-set $ddoslist64 src --exist
      $common -m set --match-set $ddoslist64 src -j $jump

      # common netmask
      $common -m set ! --match-set $hosterlist src \
        -m hashlimit --hashlimit-name $ddoslist-2m $hashlimit_opts_2m --hashlimit-srcmask $netmask \
        -j SET --add-set $ddoslist src --exist
      $common -m set ! --match-set $hosterlist src \
        -m hashlimit --hashlimit-name $ddoslist-1h $hashlimit_opts_1h --hashlimit-srcmask $netmask \
        -j SET --add-set $ddoslist src --exist
      $common -m set --match-set $ddoslist src -j $jump
    else
      $common \
        -m hashlimit --hashlimit-srcmask $netmask --hashlimit-name $ddoslist-2m $hashlimit_opts_2m \
        -j SET --add-set $ddoslist src --exist
      $common \
        -m hashlimit --hashlimit-srcmask $netmask --hashlimit-name $ddoslist-1h $hashlimit_opts_1h \
        -j SET --add-set $ddoslist src --exist
      $common -m set --match-set $ddoslist src -j $jump
    fi

    # rule 3 (only 1 connection from each of up to 8 Tor relays per ip address)

    if [[ $netmask -gt 64 ]]; then
      $common -m set --match-set $hosterlist src -m connlimit --connlimit-mask 64 --connlimit-above 8 -j $jump
    fi
    $common -m set ! --match-set $hosterlist src -m connlimit --connlimit-mask $netmask --connlimit-above 8 -j $jump

    # rule 4

    $common -j ACCEPT
  done
}

function relay_2_ip_and_port() {
  if [[ ! $relay =~ '[' || ! $relay =~ ']' || $relay =~ '.' ]]; then
    echo " relay '$relay' is invalid" >&2
    return 1
  fi
  read -r orip orport <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$relay)
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
  local family="inet6"

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
      if [[ -s $tmpdir/$name ]]; then
        xargs -r -L 1 echo "add -exist $name.tmp" <$tmpdir/$name >>$tmpfile
      fi
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

function saveCertainIpsets() {
  [[ -d $tmpdir ]] || return 1

  ipset list -n |
    grep -E -e '^torutils-ddos-v6-' -e "$manuallist" -e "^$hosterlist$" |
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
    echo 2a0c:dd40:1:b::42 2607:f018:600:8:be30:5bff:fef1:c6fa
    # Tor authorities
    echo 2001:470:164:2::2 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2610:1c0:0:5::131 2620:13:4000:6000::1000:118 2a02:16a8:662:2203::1
    getent ahostsv6 snowflake-01.torproject.net. snowflake-02.torproject.net. | awk '{ print $1 }' | sort -uV
    if relays=$(curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o -); then
      if [[ $relays =~ 'relays_published' ]]; then
        jq -r '.relays[] | .a | select(length > 1) | .[1:]' <<<$relays |
          tr ',' '\n' | grep -F ':' | tr -d ']["' |
          sort -V
      fi
    fi
  ) |
    xargs -r -n 1 -P $jobs ipset add -exist $trustlist
}

function fill_hosterlist() {
  local h comment

  # shellcheck disable=SC2034
  while read -r h comment; do
    ipset add -exist $hosterlist $h
  done <<EOF
2001:470::/32 # Hurricane Electric LLC
2001:41d0::/32 # OVHcloud
2001:67c:289c::/48 # Föreningen för digitala fri- och rättigheter (DFRI)
2a00:1b88::/32 # IELO-LIAZO SERVICES SAS
2a00:1fa0::/30 # MTS PJSC
2607:8500::/32 # Rethem Hosting LLC
2a00:63c0::/29 # IPAX GmbH
2a01:4f8::/31 # Hetzner
2602:f49b::/40 # Agfid LLC
2a03:94e0::/32 # Gigahost AS
2a04:ecc0::/29 # Feelb Sarl
2600:3c01::/32 # Akamai Connected Cloud / Linode
2604:2dc0::/32 # OVHcloud (OVH US LLC)
2605:6f08::/32 # HostPapa
2607:9d00::/32 # HostPapa
2a0d:bbc7::/32 # QuxLabs AB
2c0f:fc89::/32 # Etisalat Misr (e& Egypt)
EOF
}

function addServices() {
  local addr port service

  # local-address:local-port
  for service in ${TORUTILS_LOCAL_SERVICES_V6-}; do
    read -r addr port <<<$(sed -e 's,]:, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
      addr+="/0"
    fi
    $ipt -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT
  done

  # remote-address>local-port
  for service in ${TORUTILS_REMOTE_SERVICES_V6-}; do
    read -r addr port <<<$(sed -e 's,]>, ,' -e 's,\[, ,' <<<$service)
    if [[ $addr == "::" ]]; then
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

  local sysmon="torutils-hetznersysmon-v6"

  __create_ipset $sysmon "hash:ip maxelem 64"
  $ipt -A INPUT -m set --match-set $sysmon src -j ACCEPT
  {
    (
      echo 2a01:4f8:0:a101::5:1 2a01:4f8:0:a101::6:1 2a01:4f8:0:a101::6:2 2a01:4f8:0:a101::6:3 2a01:4f8:0:a112::c:1
      getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u
    ) |
      xargs -r -n 1 -P $jobs ipset add -exist $sysmon
  } &
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

function getConfiguredRelays6() {
  # shellcheck disable=SC2045 disable=SC2010
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null | grep -v -F -e '.sample' -e '.bak' -e '~' -e '@'); do
    if grep -q "^ServerTransportListenAddr " $f; then
      grep "^ServerTransportListenAddr " $f |
        awk '{ print $3 }' |
        grep -E "^\[[0-9a-fA-F:]{2,39}\]:[0-9]+$"
    else
      grep -v -F -e ' NoListen' -e ':auto' $f |
        grep -E "^ORPort[[:space:]]+\[[0-9a-fA-F]*:[0-9a-fA-F:]*:[0-9a-fA-F]*\]:[0-9]+[[:space:]]*" |
        awk '{ print $2 }'
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

hosterlist="torutils-hoster-v6-64" # network from where ip addreses are considerd to have /64 network prefix
manuallist="torutils-manual-v6"    # to be filled manually from outside
trustlist="torutils-trust-v6"      # Tor authorities and snowflake servers
jobs=$((1 + $(nproc) / 4))         # parallel jobs of adding ips to an ipset
# hashes and ipsets are sized with respect to the available RAM in GiB
ram=$(awk '/MemTotal/ { print int ($2 / 1024 / 1024) }' /proc/meminfo)
if [[ ${ram} -gt 8 ]]; then
  max=$((2 ** 22)) # 4M
elif [[ ${ram} -gt 1 ]]; then
  max=$((2 ** 20)) # 1M
else
  max=$((2 ** 18)) # 256K
fi
tmpdir=${TORUTILS_TMPDIR:-/var/tmp}

action=${1-}
[[ $# -gt 0 ]] && shift

if [[ $action != "update" && $action != "save" ]]; then
  # check if iptables works or if its legacy variant is needed
  ipt="ip6tables"
  set +e
  $ipt -nv -L INPUT >/dev/null
  rc=$?
  set -e
  if [[ $rc -eq 4 ]]; then
    ipt+="-legacy"
    if ! $ipt -nv -L INPUT >/dev/null; then
      echo " $ipt is not working" >&2
      exit 1
    fi
  elif [[ $rc -ne 0 ]]; then
    echo " $ipt is not working, rc=$rc" >&2
    exit 1
  fi
fi

case $action in
start)
  trap bailOut INT QUIT TERM EXIT
  clearRules
  jump=${TORUTILS_SAVE_RUN:-DROP}
  addCommon
  addHetzner
  addServices
  addTor ${*:-${TORUTILS_RELAYS_V6-$(getConfiguredRelays6)}}
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
  saveCertainIpsets
  ;;
*)
  printRuleStatistics
  ;;
esac

while fg &>/dev/null; do
  :
done
