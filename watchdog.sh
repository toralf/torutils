#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart Tor if system stucks

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type logger mpstat service >/dev/null

i=0
while :; do
  read -r iowait < <(mpstat --dec=0 -P 'ALL' 60 1 | awk '/^Average:  *all / { print $6 }')

  if ((iowait >= 25)); then
    ((++i))
  elif ((iowait <= 15 && i > 0)); then
    ((i--))
  fi

  if ((i > 10)); then
    logger -s "WARNING: $(basename $0) is restarting Tor"
    service tor stop
    sleep 30
    service tor start
    sleep 900
    i=0
  fi
done
