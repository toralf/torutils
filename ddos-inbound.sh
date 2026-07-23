#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# count inbound connections per remote ip address

function show() {
  local relay=$1

  local v=""
  if [[ $relay =~ "[" ]]; then
    v="6"
  fi

  local conns=0
  local ips=0
  local sum=0
  while read -r conns ip; do
    if [[ $conns -gt $limit ]]; then
      printf "%-10s %-41s %5i\n" "ip$v" "$ip" "$conns"
      ((++ips))
      ((sum += conns))
    fi
  done < <(
    ss --no-header --tcp -${v:-4} --numeric |
      grep "^ESTAB" |
      grep -F " $relay " |
      awk '{ print $5 }' | sort -n | sed -E -e 's,:[[:digit:]]+$,,g' | uniq -c
  )

  if [[ $ips -gt 0 ]]; then
    printf "relay:%-42s           ips:%-5i conns:%-5i\n\n" "$relay" "$ips" "$sum"
  fi
}

function getConfiguredRelays() {
  # shellcheck disable=SC2045 disable=SC2010
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null | grep -v -F -e '.sample' -e '.bak' -e '~' -e '@'); do
    # OR port and address are defined either together in 1 line or in 2 different lines
    if orport=$(grep "^ORPort *" $f | grep -v -F -e ' NoListen' -e '[' -e ':auto' | grep -E "^ORPort[[:space:]]+.+[[:space:]]*"); then
      if grep -q -E "^ORPort[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+[[:space:]]*" <<<$orport; then
        awk '{ print $2 }' <<<$orport
      elif address=$(grep -E "^Address[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*" $f); then
        echo $(awk '{ print $2 }' <<<$address):$(awk '{ print $2 }' <<<$orport)
      fi
    fi
  done
}

function getConfiguredRelays6() {
  # shellcheck disable=SC2045 disable=SC2010
  for f in $(ls /etc/tor/torrc* /etc/tor/instances/*/torrc 2>/dev/null | grep -v -F -e '.sample' -e '.bak' -e '~' -e '@'); do
    grep -v -F -e ' NoListen' -e ':auto' $f |
      grep -E "^ORPort[[:space:]]+\[[0-9a-fA-F]*:[0-9a-fA-F:]*:[0-9a-fA-F]*\]:[0-9]+[[:space:]]*" |
      awk '{ print $2 }'
  done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=9
relays=$(
  getConfiguredRelays
  getConfiguredRelays6
)

while getopts l:r: opt; do
  case $opt in
  l) limit=$((OPTARG + 0)) ;;
  r) relays="$OPTARG" ;;
  *)
    echo "unknown parameter '$opt'"
    exit 1
    ;;
  esac
done

for relay in $relays; do
  show $relay
done
