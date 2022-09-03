#!/bin/bash
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
git pull 1>/dev/null

v=$(tor --version | head -n 1 | cut -f2 -d'(' | tr -d '(git\-).')
h=$(git describe HEAD | sed "s,^.*-g,,g")

if [[ -z $v || -n $h && ! $v =~ $h ]]; then
  date
  echo -e "update $v..$h\n"
  unset GIT_PAGER
  export PAGER=cat
  git log --oneline $v..$h
  git diff --stat $v..$h
  emerge -1 net-vpn/tor
  echo -e "\nrestart Tor\n"
  /sbin/rc-service tor  restart
  echo -e "\nrestart Tor2\n"
  /sbin/rc-service tor2 restart
  date
fi
