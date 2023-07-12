#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# update Tor and restart Tor relay(s) under Gentoo Linux (OpenRC)

function restart() {
  export GRACEFUL_TIMEOUT=20

  for i in {1..4}; do
    service=tor$i
    echo
    echo "----------------------------"
    date
    echo " restarting $service"
    echo
    if ! rc-service $service restart; then
      local pid=$(cat /run/tor/$service.pid)
      if kill -0 $pid; then
        echo " get roughly with pid $pid"
        kill -9 $pid
        sleep 1
      else
        rm /run/tor/$service.pid
        echo " $pid for $service was invalid"
      fi
      if ! rc-service $service zap start; then
        echo "zap failed for $service"
      fi
    fi
  done
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

export GIT_PAGER="cat"

if [[ ! -d ~/tor ]]; then
  cd ~
  git clone https://git.torproject.org/tor.git
else
  tmpfile=$(mktemp /tmp/$(basename $0).XXXXXX)
  cd ~/tor
  git pull &>$tmpfile
  range=$(grep -e "^Updating .*\.\..*$" $tmpfile | cut -f 2 -d ' ' -s)
  if [[ -n $range ]]; then
    cat $tmpfile
    echo
    git log $range
    echo

    rm $tmpfile
  else
    rm $tmpfile
    # rebuild if libevent was updated (and tor refuses to start w/o being recompiled against latest libevent)
    if tor --version 1>/dev/null; then
      exit 0
    fi
  fi
fi

echo
date
emerge -1 net-vpn/tor

restart

echo
date
echo " all work done"
