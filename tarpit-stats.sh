#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: print number of unique IPvx addresses per network block of tarpit set(s)

# e.g.:
#   NETMASK=24 MIN=9 ./tarpit-stats.sh ~/tmp/tor-relays/fw/*/torutils-tarpit-v4 | head -n 40
#   NETMASK=64 ./tarpit-stats.sh /var/tmp/torutils-tarpit-v6

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin:~/bin

[[ $# -gt 0 ]]

if grep -q ':' $1; then
  netmask=${NETMASK:-48}
  ip_v=6
elif grep -qF '.' $1; then
  netmask=${NETMASK:-16}
  ip_v=4
else
  exit 2
fi

cut -f 1 -d ' ' $@ |
  sort |
  # same address must be in at least than x sets
  uniq -c | awk '{ if ($1 >= '${MIN:-1}') { print $2 } }' |
  if [[ $ip_v == 4 ]]; then
    # IPv4 block
    if ((netmask == 24)); then
      grep -Eo "^[0-9]+\.[0-9]+\.[0-9]+" | sed -e 's,$,.0/24,'
    else
      grep -Eo "^[0-9]+\.[0-9]+" | sed -e 's,$,.0.0/16,'
    fi
  elif [[ $ip_v == 6 ]]; then
    # IPv6 block
    if ((netmask == 64)); then
      grep -Eo "^[0-9a-f]+:[0-9a-f]+:[0-9a-f]*:[0-9a-f]*" | sed -e 's,[:]*$,::/64,'
    else
      grep -Eo "^[0-9a-f]+:[0-9a-f]+:[0-9a-f]*" | sed -e 's,[:]*$,::/48,'
    fi
  fi |
  uniq -c | sort -bnr
