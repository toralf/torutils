#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# this works under Gentoo Linux only and and only
# if net-vpn/tor-9999 is unmasked (https://github.com/toralf/tgro/blob/main/net-vpn/tor/)
# but then: keep Tor service(s) at -git HEAD


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

cd ~
if [[ ! -d ~/tor ]]; then
  git clone https://git.torproject.org/tor.git
fi
cd ~/tor

if git pull 2>&1 | grep -q 'Already up to date.'; then
  exit 0
fi

version=$(tor --version | head -n 1)
if grep -q 'git' <<< $version; then
  version=$(cut -f2 -d'(' <<< $version | tr -d '(git\-).')
fi
head=$(git describe HEAD | sed "s,^.*-g,,g")

date

echo -e "update $version..$head\n"
unset GIT_PAGER
export PAGER=cat
git log --oneline $version..$head 2>/dev/null && git diff --stat $version..$head

emerge -1 net-vpn/tor
echo -e "\nrestart Tor\n"
/sbin/rc-service tor  restart
echo -e "\nrestart Tor2\n"
/sbin/rc-service tor2 restart

date

