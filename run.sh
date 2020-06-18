#!/bin/sh
#
# set -x


# start or stop fuzzer(s) to achieve $1 runnning instances


set -euf
cd $(dirname $0)

if [[ $# -ne 1 ]]; then
  exit 1
fi

./fuzz.sh -l -f -a

pids=$(pgrep --parent 1 -f '/usr/bin/afl-fuzz -i') || true

desired=$1
let "diff = $desired - $(echo $pids | wc -w)"

if   [[ $diff -gt 0 ]]; then
  ./fuzz.sh -u -c -s $diff

elif [[ $diff -lt 0 ]]; then
  victims=$(echo $pids | xargs -n 1 | shuf -n ${diff##*-})
  if [[ -n "$victims" ]]; then
    kill -15 $victims || true
    sleep 2
    ./fuzz.sh -l -f -a
  fi
fi
