#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# update and restart Tor under Gentoo Linux (OpenRC)



function rebuild()   {
  echo
  date
  emerge -1 net-vpn/tor
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ ! -d ~/tor ]]; then
  cd ~
  git clone https://git.torproject.org/tor.git
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
    rebuild

    for i in tor tor2 tor3
    do
      echo
      date
      echo " restart $i"
      rc-service $i restart || true
    done
  else
    rm $tmpfile
    # force a rebuild if eg. libevent was updated and tor would fail at next start
    if tor --version 1>/dev/null; then
      exit 0
    fi
    rebuild
  fi
fi

echo
date
echo " all work done"
