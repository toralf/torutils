#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# prevent netscan abuse hits

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
  # having the start date in the iptables output is the desired intention of this rule
  $ipt -A OUTPUT --out-interface lo -m comment --comment "egress IPv4 $(date -R)" -j ACCEPT

  # do not touch established connections
  $ipt -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # current Hetzner threshold seems to be 150 connections within 4 min to a /22 network block
  # set our limit to 2/3 of the threshold
  limit=${2:-$((150 * 2 / 3 / 4))}

  # slew bursts e.g. caused by a reboot
  # allow 1/6 of limit immediately, then 1/6 per minute, so after 4 minutes about 5/6 of the limit is reached at max
  default="45.84.107.0/24 64.65.0.0/22 64.65.60.0/22 96.9.98.0/24 109.70.100/24 171.25.193.0/24 185.220.101.0/24 192.42.116.0/24"
  for item in ${EGRESS_SUBNET_SLEW-$default}; do
    read -r net mask <<<$(tr '/' ' ' <<<$item)
    $ipt -A OUTPUT -p tcp --dst $net/${mask:-22} -m conntrack --ctstate NEW -m hashlimit --hashlimit-name tor-egress --hashlimit-mode dstip,dstport --hashlimit-dstmask ${mask:-22} --hashlimit-above $limit/minute --hashlimit-burst $limit -j REJECT
    # $ipt -A OUTPUT -p tcp --dst $net/${mask:-22} # counter to debug stat numbers
  done
fi
