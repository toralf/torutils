#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# update and restart Tor under Gentoo Linux (OpenRC)


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ ! -d ~/tor ]]; then
  cd ~
  echo " cloning ..."
  git clone -q https://git.torproject.org/tor.git
else
  cd ~/tor
  tmpfile=$(mktemp /tmp/$(basename $0).XXXXXX)
  git pull &> $tmpfile
  range=$(grep -e "^Updating .*\.\..*$" $tmpfile | cut -f2 -d' ' -s)
  if [[ -n $range ]]; then
    cat $tmpfile
    echo
    git log $range
    echo
    rm $tmpfile
  else
    rm $tmpfile
    if [[ $# -eq 0 ]]; then
      exit 0
    fi
  fi
fi

echo
date
cd ~
emerge -1 net-vpn/tor

set +e

echo
date
echo " restart Tor"
rc-service tor  restart
echo " restart Tor 2"
rc-service tor2 restart
echo " restart Tor 3"
rc-service tor3 restart

echo
date
echo " restarting orstatus"
pkill -ef $(dirname $0)/orstatus.py
export PYTHONPATH=/root/stem
for port in 9051 29051 29051
do
  $(dirname $0)/orstatus.py --ctrlport $port --address ::1 >> /tmp/orstatus-$port &
done

echo
date
echo " all work done"
