#!/bin/sh
# set -x


# start or stop fuzzer(s) to achieve $1 runnning instances


function CountPids()  {
  pgrep --parent 1 -f '/usr/bin/afl-fuzz -i' | xargs
}


#######################################################################
set -euf

if [[ $# -ne 1 ]]; then
  exit 1
fi

cd $(dirname $0)

./fuzz.sh -g -f -a
pids=$(CountPids $1)
((diff = $1 - $(wc -w <<< $pids)))

if [[ $diff -gt 0 ]]; then
  # first restart, then maybe update and eventually start more
  ./fuzz.sh -r $diff
  sleep 10
  pids=$(CountPids $1)
  if ((diff = $1 - $(wc -w <<< $pids))); then
    ./fuzz.sh -u -s $diff
  fi
  # plots are available after 60 sec
  sleep 70
  ./fuzz.sh -g

elif [[ $diff -lt 0 ]]; then
  victims=$(ps -h -o etimes,pid --pid $(tr ' ' ',' <<< $pids) | sort -n | head -n ${diff##*-} | awk ' { print $2 } ' | xargs)
  if [[ -n "$victims" ]]; then
    echo "$0 $(date) will kill pid/s: $victims"
    kill -15 $victims || true
    sleep 10
    ./fuzz.sh -f -a
  fi
fi
