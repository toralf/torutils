#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart a crashed service under Gentoo Linux (OpenRC)

function healService() {
  local service=${1?}

  local msg="$0: detected crashed $service"
  echo "$msg" >&2
  logger "$msg"
  sleep 30
  rc-service -qq $s status
  if [[ $? -eq 32 ]]; then
    msg="$0: restart crashed $service"
    echo "$msg" >&2
    logger "$msg"
    rc-service $s zap start
  else
    msg="$0: healed w/o our help $service"
    echo "$msg" >&2
    logger "$msg"
  fi
}

#######################################################################
#
set -u
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

while :; do
  if [[ "$(runlevel)" == "N 3" ]]; then
    for s in ssh unbound $(find /etc/init.d -name 'tor*' -print0 | xargs -r -n 1 --null basename); do
      rc-service -qq $s status
      if [[ $? -eq 32 ]]; then
        healService $s &
      fi
    done
  fi
  sleep 60
done
