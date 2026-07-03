#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart Tor if CPU idle is lower than $2 for (cumulated) $1 minutes

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type logger mpstat service tor >/dev/null

# $> mpstat --dec=0 -P "ALL" 10 1
# Linux 7.0.10+deb13-cloud-amd64 (i30)    06/18/26        _x86_64_        (1 CPU)
#
# 20:52:22     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# 20:52:32     all      38       0      28       1       0      33       0       0       0       0
# 20:52:32       0      38       0      28       1       0      33       0       0       0       0
#
# Average:     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# Average:     all      38       0      28       1       0      33       0       0       0       0
# Average:       0      38       0      28       1       0      33       0       0       0       0

max=${1:-15} # minutes
i=0
while :; do
  idle=$(mpstat --dec=0 -P "ALL" 59 1 | awk '/^Average:  *all / { print $12 }')

  # watch
  if [[ ${idle} -lt 5 ]]; then
    ((i++))
    if [[ $i -ge ${max} ]]; then
      logger -s "WARNING: $(basename $0) is restarting Tor"
      service tor stop
      sleep 30
      service tor start
      sleep 120
      i=0
    fi

  # credit decrease
  elif [[ $i -gt 0 && ${idle} -gt 20 ]]; then
    ((i--))
  fi

done
