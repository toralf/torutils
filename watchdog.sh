#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart Tor if CPU is under pressure or metrics can't be scraped

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type curl logger mpstat service tor >/dev/null

i=0
j=0
while :; do
  read -r iowait idle < <(mpstat --dec=0 -P 'ALL' 60 1 | awk '/^Average:  *all / { print $6, $12 }')

  if ((idle <= 5 || iowait >= 30)); then
    ((++i))
  elif ((idle >= 20 && iowait <= 20 && i > 0)); then
    ((i--))
  fi

  if grep -q "^MetricsPort 127.0.0.1:9052$" /etc/tor/torrc; then
    if curl -m 3 -s localhost:9052/metrics | grep -q .; then
      j=0
    else
      ((++j))
    fi
  fi

  if ((i + j > 10)); then
    logger -s "WARNING: $(basename $0) is restarting Tor"
    service tor stop
    sleep 30
    service tor start
    sleep 900
    i=0
  fi
done
