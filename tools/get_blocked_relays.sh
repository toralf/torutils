#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: test if an nftables set contains Tor relay address/es
#
# example: ./tools/get_found_relays.sh root@mr-fox v6

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

type jq nft >/dev/null

host=${1?RELAY IS MISSING}  # host string, e.g. "user@hostname"
ipver=${2?IPVER IS MISSING} # "v4" or "v6"
expires=${3:-0}             # integer between 0 and 23

# get known Tor relays
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

# get set content
ddos=/tmp/ddos.$ipver.$srv.json
if ! ts=$(stat -c %Y $ddos 2>/dev/null); then
  ts=0
fi
if [[ ! -s $ddos || $((EPOCHSECONDS - ts > 60)) ]]; then
  # shellcheck disable=SC2029
  if ! ssh $host "nft -j -n list set inet ingress_filter ddos_$ipver" >$ddos; then
    echo " cannot query $host for $ipver" >&2
    exit 1
  fi
fi

# grep for address7/es where expires fits the desired value
filtered=/tmp/ddos.$ipver.$srv.filtered.txt
jq -r ".nftables[].set.elem[]? | select(.elem.expires > $expires * 3600) | .elem.val" <$ddos | sort >$filtered
echo "$(wc -l <$filtered) addresses in $filtered"

# false positives likely for IPv6 b/c the ddos_v6 set contains /64 network blocks
found=/tmp/relays.$ipver.$srv.found.txt
grep -f $filtered $known |
  sort -uV >$found
echo "$(wc -l <$found) matches in $found"
