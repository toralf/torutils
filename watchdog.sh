#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart Tor if CPU idle is lower than $2 for (cumulated) $1 minutes

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type logger mpstat service tor >/dev/null

# $ ssh i30 "mpstat --dec=0 -P 'ALL' 59 1"
# Linux 7.0.12+deb13-cloud-amd64 (i30)    07/04/26        _x86_64_        (1 CPU)
#
# 09:45:50     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# 09:46:49     all      25       0      17      18       0      22       0       0       0      18
# 09:46:49       0      25       0      17      18       0      22       0       0       0      18
#
# Average:     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# Average:     all      25       0      17      18       0      22       0       0       0      18
# Average:       0      25       0      17      18       0      22       0       0       0      18

i=0
while :; do
  read -r iowait idle < <(mpstat --dec=0 -P 'ALL' 60 1 | awk '/^Average:  *all / { print $6, $12 }')

  if ((idle <= 5 || iowait >= 30)); then
    ((++i))
    if ((i >= 10)); then
      logger -s "WARNING: $(basename $0) is restarting Tor"
      service tor stop
      sleep 30
      service tor start
      sleep 120
      i=0
    fi

  elif ((idle >= 20 && iowait <= 20 && i > 0)); then
    ((i--))
  fi
done
