#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# handle netscan abuse cases

# examples:
#
# clear chain OUTPUT:
# /opt/torutils/ipv4-rules-egress.sh
#
# apply to a /22 and a /24 network segment, limit the amount of new connection per minute to 20
# EGRESS_SUBNET_SLEW="1.2.3.4/22 5.6.7.8" /opt/torutils/ipv4-rules-egress.sh start 20

#######################################################################
set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066

ipt="iptables"

# default policy
$ipt -P OUTPUT ACCEPT

# flush and clear stats
$ipt -F OUTPUT
$ipt -Z OUTPUT

if [[ ${1-} == "start" ]]; then
  # allow loopback
  $ipt -A OUTPUT --out-interface lo -m comment --comment "egress IPv4 $(date -R)" -j ACCEPT

  # do not touch established connections
  $ipt -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # slew bursts e.g. after a reboot
  for item in ${EGRESS_SUBNET_SLEW-}; do
    read -r net mask <<<$(tr '/' ' ' <<<$item)
    $ipt -A OUTPUT -p tcp --dst $net/${mask:-24} -m conntrack --ctstate NEW -m hashlimit --hashlimit-name tor-egress --hashlimit-mode dstip,dstport --hashlimit-dstmask ${mask:-24} --hashlimit-above ${2:-25}/minute --hashlimit-burst 1 -j REJECT
    # $ipt -A OUTPUT -p tcp --dst $net/${mask:-24} -j ACCEPT # stats for debug purpose
  done
fi
