#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart Tor if system stucks
# Caution:
#   This is not a general solution.
#   This script might be triggered remotely by DDoS'ing a Tor server.

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type logger mpstat service >/dev/null

[[ ${1-} == "i_know_what_i_am_doing" ]]

i=0
while :; do
  read -r iowait idle < <(mpstat --dec=0 -P 'ALL' 60 1 | awk '/^Average:  *all / { print $6, $12 }')

  if ((iowait > 25)); then
    ((++i))
    if ((idle < 5)); then
      ((i += 2))
    fi
  elif ((iowait < 20 && idle > 10 && i > 0)); then
    ((i--))
  fi

  if ((i > 10)); then
    logger -s "WARNING: $(basename $0) is restarting Tor"
    service tor stop
    sleep 30
    service tor start
    sleep 600
    i=0
  fi
done
