#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: test set of blocked addresses for relays
#
# example: ./tools/get_blocked_relays.sh root@mr-fox v6

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

host=${1?RELAY IS MISSING}
ipver=${2?IPVER IS MISSING}

# update current list of relay addresses

known=/tmp/relays.$ipver.known.txt
if ! ts=$(stat -c %Y $known 2>/dev/null); then
  ts=0
fi
if [[ ! -s $known || $((EPOCHSECONDS - ts > 86400)) ]]; then
  curl -s 'https://onionoo.torproject.org/details?fields=or_addresses' |
    if [[ $ipver == "v4" ]]; then
      jq -r '.relays[] | .or_addresses[] | select(contains("[") | not) | split(":")[0]'
    elif [[ $ipver == "v6" ]]; then
      jq -r '.relays[] | .or_addresses[] | select(contains("[")) | split("]")[0]' |
        tr -d '['
    else
      echo " $ipver not implemented" >&2
      exit 1
    fi |
    sort >$known
fi
echo "$(wc -l <$known) relays in $known"

# strip away auth
srv="${host#*@}"

# get content of nftables set

ddos=/tmp/ddos.$ipver.$srv.txt
# shellcheck disable=SC2029
if ! ssh $host "nft -j -n list set inet ingress_filter ddos_$ipver | jq -r '.nftables[].set.elem[]?.elem.val'" | sort >$ddos; then
  echo " cannot query $host" >&2
  exit 1
fi
echo "$(wc -l <$ddos) addresses in $ddos"

# compare

blocked=/tmp/relays.$ipver.$srv.blocked.txt
comm -12 $known $ddos |
  sort -V >$blocked
echo "$(wc -l <$blocked) relays in $blocked"
