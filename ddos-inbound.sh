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
      printf "%-10s %-41s %5i\n" "ip$v" "$ip" "$conns"
      (( ++ips ))
      (( sum += conns ))
    fi
  done < <(
    ss --no-header --tcp -${v:-4} --numeric |
    grep "^ESTAB" |
    grep -F " $relay " |
    awk '{ print $5 }' | sort | sed -E -e 's,:[[:digit:]]+$,,g' | uniq -c
  )

  if [[ $ips -gt 0 ]]; then
    printf "relay:%-42s           ips:%-5i conns:%-5i\n\n" "$relay" "$ips" "$sum"
  fi
}



function getConfiguredRelays()  {
  for f in /etc/tor/torrc*
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


function getConfiguredRelays6()  {
  grep -h -e "^ORPort *" /etc/tor/torrc* | grep -v ' NoListen' |
  grep -P "^ORPort\s+\[[0-9a-f]*:[0-9a-f:]*:[0-9a-f]*\]:\d+\s*" |
  awk '{ print $2 }'
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=4
relays=$(getConfiguredRelays; getConfiguredRelays6)

while getopts l:r: opt
do
  case $opt in
    l)  limit=$(( OPTARG+0 )) ;;
    r)  relays="$OPTARG" ;;
    *)  echo "unknown parameter '$opt'"; exit 1 ;;
  esac
done

for relay in $relays
do
  show $relay
done
