#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# update and restart Tor under Gentoo Linux (OpenRC)



function rebuild()   {
  echo
  date
  emerge -1 net-vpn/tor
}


function restart()  {
  for i in tor tor2 tor3
  do
    echo
    date
    echo " restart $i"
    if ! rc-service $i restart; then
      if pid=$(cat /run/tor/$i.pid); then
        echo " get roughly with pid $pid"
        if kill -9 $pid; then
          sleep 1
          rc-service $i zap start
        else
          echo " can't kill $pid ?!"
        fi
      else
        echo " no pid ?!"
      fi
    fi
  done
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
  else
    rm $tmpfile
    # pass to rebuild if eg. libevent was updated and tor would fail at next start
    if tor --version 1>/dev/null; then
      exit 0
    fi
  fi
fi

rebuild
restart

echo
date
echo " all work done"
