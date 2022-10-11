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
      (( sum = sum + conns ))
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


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=2

relays=$(grep -e "^ORPort" /etc/tor/torrc* | awk '{ print $2 }' | xargs)

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
