#!/bin/sh
#
# set -x


# start or stop fuzzers to have $1 runnning instances


if [[ $# -ne 1 ]]; then
  exit 1
fi

desired=$1

# wrap up last hour
$(dirname $0)/fuzz.sh -c -a

pids=$(pgrep -f '/usr/bin/afl-fuzz -i /home/torproject/tor-fuzz-corpora/')
let "diff = $desired - $(echo $pids | wc -w)"

if   [[ $diff -gt 0 ]]; then
  $(dirname $0)/fuzz.sh -u -s $diff

elif [[ $diff -lt 0 ]]; then
  victims=$(echo $pids | xargs -n 1 | shuf -n ${diff##*-})
  if [[ -n "$victims" ]]; then
    kill -15 $victims
    sleep 5
    $(dirname $0)/fuzz.sh -c -a
  fi
fi
