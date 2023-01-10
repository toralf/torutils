#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# update and restart Tor under Gentoo Linux (OpenRC)


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

echo
date
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
    rm $tmpfile
  else
    rm $tmpfile
    exit 0
  fi
fi

echo
date
cd ~
emerge -1 net-vpn/tor

echo
date
echo " restart Tor"
rc-service tor restart
echo " restart Tor2"
rc-service tor2 restart

echo
date
echo " restarting orstatus"
pkill -ef $(dirname $0)/orstatus.py || true
export PYTHONPATH=/root/stem
nohup $(dirname $0)/orstatus.py --ctrlport  9051 --address ::1 >> /tmp/orstatus-9051  &
nohup $(dirname $0)/orstatus.py --ctrlport 29051 --address ::1 >> /tmp/orstatus-29051 &

echo
date
echo " all work done"
