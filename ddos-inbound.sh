#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# count inbound to local ORPort per remote ip address

function show() {
  local relay=$1

  local v=""
  if [[ $relay =~ '[' ]]; then
    v="6"
  fi
  local sum=0
  local ips=0

  while read -r conns ip
  do
    if [[ $conns -gt $limit ]]; then
      printf "%-10s %-40s %5i\n" ip$v $ip $conns
      (( ++ips ))
      (( sum += conns ))
    fi
  done < <(
    ss --no-header --tcp -${v:-4} --numeric |
    grep "^ESTAB" |
    grep -F " $relay " |
    awk '{ print $5 }' | sort | sed 's,:[[:digit:]]*$,,g' | uniq -c
  )

  if [[ $ips -gt 0 ]]; then
    printf "relay:%-42s           ips:%-5i conns:%-5i\n\n" $relay $ips $sum
  fi
}


function getConfiguredRelays()  {
  (
    set +e

    grep -hE "^ORPort\s+" /etc/tor/torrc* |
    sed -e "s,^ORPort\s*,," |
    sed -e 's,\s*#.*,,' |
    grep -v ' ' |
    while read line
    do
      grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$" <<< $line
      grep -E "^[0-9]+$" <<< $line | sed 's,^,0.0.0.0:,g'

      grep -E "^\[[0-9a-f:]+\]:[0-9]+$" <<< $line
      grep -E "^[0-9]+$" <<< $line | sed 's,^,[::]:,g'
    done |
    sort -u | xargs
  )
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=2

relays=$(getConfiguredRelays)

while getopts l:r: opt
do
  case $opt in
    l)  limit=$OPTARG ;;
    r)  relays="$OPTARG" ;;
    *)  echo "unknown parameter '$opt'"; exit 1 ;;
  esac
done

for relay in $relays
do
  show $relay
done
