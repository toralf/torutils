#!/bin/sh
#
# set -x


# start or stop fuzzer(s) to achieve $1 runnning instances


set -euf

if [[ $# -ne 1 ]]; then
  exit 1
fi

cd $(dirname $0)

./fuzz.sh -f -a -g

pids=$(pgrep --parent 1 -f '/usr/bin/afl-fuzz -i') || true
let "diff = $1 - $(echo $pids | wc -w)" || true

if   [[ $diff -gt 0 ]]; then
  ./fuzz.sh -u -c -s $diff

elif [[ $diff -lt 0 ]]; then
  victims=$(echo $pids | xargs -n 1 | shuf -n ${diff##*-})
  if [[ -n "$victims" ]]; then
    kill -15 $victims || true
    sleep 5
    ./fuzz.sh -a
  fi
fi
