#!/bin/sh
#
# set -x


# start or stop fuzzer(s) to achieve $1 runnning instances


function CountPids()  {
  pids=$(pgrep --parent 1 -f '/usr/bin/afl-fuzz -i') || true
  let "diff = $1 - $(wc -w <<< $pids)" || true
}


#######################################################################
set -euf

if [[ $# -ne 1 ]]; then
  exit 1
fi

cd $(dirname $0)

./fuzz.sh -f -a -g

CountPids $1
if [[ $diff -gt 0 ]]; then
  ./fuzz.sh -r $diff
  CountPids $1
  if [[ $diff -gt 0 ]]; then
    ./fuzz.sh -u -s $diff
  fi

elif [[ $diff -lt 0 ]]; then
  victims=$(echo $pids | xargs -n 1 | shuf -n ${diff##*-})
  if [[ -n "$victims" ]]; then
    echo "$0 $(date) will kill: $victims"
    kill -15 $victims || true
    sleep 15
    ./fuzz.sh -a
  fi
fi
