#!/bin/sh
#
# set -x

# restart or stop fuzzers to have $1 running instances

if [[ $# -ne 1 ]]; then
  exit 1
fi

$(dirname $0)/fuzz.sh -c -a

jobs=$1
let "n = $jobs - $(pgrep -ac afl-fuzz)"

if   [[ $n -gt 0 ]]; then
  # update before starting a new instance
  $(dirname $0)/fuzz.sh -u -s $n
elif [[ $n -lt 0 ]]; then
  # kill $n arbitrarily choosen instances
  kill -15 $(pgrep "afl-fuzz" | xargs -n 1 | shuf -n ${n##*-})
fi

$(dirname $0)/fuzz.sh -c -a
