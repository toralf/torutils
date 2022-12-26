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
  git clone https://git.torproject.org/tor.git
fi
cd ~/tor

updating=$(git pull | grep -e "^Updating .*\.\..*$" | cut -f2 -d' ')
if [[ -z $updating ]]; then
  exit 0
fi

echo
date
echo -e "update $updating\n"
unset GIT_PAGER
export PAGER=cat
git log --oneline $updating
git diff --stat $updating

emerge -1 net-vpn/tor

echo -e "\nrestart Tor\n"
rc-service tor restart &
echo -e "\nrestart Tor2\n"
rc-service tor2 restart

iptables -Z
ip6tables -Z

echo
date
echo -e "\n restarting orstatus\n"
pkill -f /opt/torutils/orstatus.py
export PYTHONPATH=/root/stem
nohup /opt/torutils/orstatus.py --ctrlport  9051 --address ::1 >> /tmp/orstatus-9051 &
nohup /opt/torutils/orstatus.py --ctrlport 29051 --address ::1 >> /tmp/orstatus-29051 &

echo
date
echo -e "\n all work done\n"
