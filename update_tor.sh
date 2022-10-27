#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# update and restart Tor under Gentoo Linux


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

cd ~
if [[ ! -d ~/tor ]]; then
  git clone https://git.torproject.org/tor.git
fi
cd ~/tor

updating=$(git pull | grep -e "^Updating .*\.\..*$" | cut -f2 -d' ')
if [[ -z $updating ]]; then
  exit 0
fi

date
echo -e "update $updating\n"
unset GIT_PAGER
export PAGER=cat
git log --oneline $updating
git diff --stat $updating

emerge -1 net-vpn/tor
echo -e "\nrestart Tor\n"
/sbin/rc-service tor  restart
echo -e "\nrestart Tor2\n"
/sbin/rc-service tor2 restart

date
