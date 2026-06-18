#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart Tor if CPU is stalled (usually at tiny systems)

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type mpstat >/dev/null

# $> mpstat -P ALL
# Linux 7.0.10+deb13-cloud-amd64 ...
#
# 18:37:05     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# 18:37:05     all   15.37    0.22   13.23    1.80    0.00   13.23    0.00    0.00    0.00   56.15
# 18:37:05       0   15.37    0.22   13.23    1.80    0.00   13.23    0.00    0.00    0.00   56.15

# Trigger a restart if idle is lower than $2 for $1 consecutive times.
max=${1:-15}
i=0
while :; do
  if [[ $(mpstat -P "ALL" | awk '/ all / { printf ("%i", $12) }') -lt ${2:-5} ]]; then
    if ((i++ > max)); then
      logger -s -t watchdog "WARNING: restarting Tor"
      service tor stop
      sleep 30
      service tor start
      i=0
    fi

  else
    i=0
  fi

  sleep 60
done
