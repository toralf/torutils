#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# handle netscan abuse cases

# examples:
#
# /opt/torutils/ipv4-rules-egress.sh
# EGRESS_SUBNET_DROP="1.2.3.4/24" /opt/torutils/ipv4-rules-egress.sh start
# EGRESS_SUBNET_SLEW="5.6.7.8/20" /opt/torutils/ipv4-rules-egress.sh start 16

#######################################################################
set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

umask 066

ipt="iptables"

# flush and clear stats
$ipt -F OUTPUT
$ipt -Z OUTPUT

# default policy
$ipt -P OUTPUT ACCEPT

if [[ ${1-} == "start" ]]; then
  # block entirely
  for item in ${EGRESS_SUBNET_DROP-}; do
    read -r net mask <<<$(tr '/' ' ' <<<$item)
    $ipt -A OUTPUT -p tcp --destination $net/$mask -j DROP
  done

  # ramp on slowly
  for item in ${EGRESS_SUBNET_SLEW-}; do
    read -r net mask <<<$(tr '/' ' ' <<<$item)
    $ipt -A OUTPUT -p tcp --dst $net/${mask:-24} -m hashlimit --hashlimit-name tor-egress --hashlimit-mode dstip,dstport --hashlimit-dstmask ${mask:-24} --hashlimit-above ${2:-8}/minute -j REJECT
  done
fi
