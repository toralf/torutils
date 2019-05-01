#!/bin/sh
#
# set -x

# start/stop fuzzers to achieve $1 running instances

/opt/torutils/fuzz.sh -c -a

if [[ $# -ne 1 ]]; then
  exit 1
fi

jobs=${1:-0}
let "n = $jobs - $(pgrep -c afl-fuzz)"

if    [[ $n -gt 0 ]]; then
  /opt/torutils/fuzz.sh -u -s $n

elif  [[ $n -ne 0 ]]; then
  n=$(echo "$n" | sed -e 's/-//g')
  kill -15 $(pgrep afl-fuzz | xargs -n 1 | shuf -n $n)
  sleep 2
  /opt/torutils/fuzz.sh -a
fi
