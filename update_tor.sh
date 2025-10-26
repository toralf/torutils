#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# update Tor and restart Tor relay(s) under Gentoo Linux (OpenRC)

function restart() {
  export GRACEFUL_TIMEOUT=20

  # shellcheck disable=SC2011
  (
    set +f
    ls /etc/init.d/tor{,?}
  ) |
    xargs -r -n 1 basename |
    while read -r service; do
      echo
      echo "----------------------------"
      date
      echo " $service"
      echo

      if ! rc-service $service status; then
        echo -e "\n skipped"
      else
        if ! rc-service $service restart; then
          sleep 5
          if pid=$(</run/tor/$service.pid); then
            if kill -0 $pid; then
              echo " kill pid $pid"
              kill -9 $pid
              sleep 5
            else
              rm /run/tor/$service.pid
              echo " stale pid $pid"
            fi
          fi
          if ! rc-service $service zap start; then
            echo "zap start failed"
          fi
        fi
      fi
      echo
    done
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

hash -r rc-service smart-live-rebuild

if smart-live-rebuild --no-color --pretend -f net-vpn/tor 2>&1 | grep -q 'No updates found'; then
  exit 0
fi

echo
date
smart-live-rebuild --no-color -f net-vpn/tor
restart
echo
date
echo " all work done"
