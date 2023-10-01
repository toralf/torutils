#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart a crashed service under Gentoo Linux (OpenRC)

function log() {
  local msg="$*"

  echo "$msg" >&2
  logger "$msg"
}

function healService() {
  local service=${1?}

  log "$0: detected crashed $service"
  sleep 30
  rc-service -qq $s status
  if [[ $? -eq 32 ]]; then
    log "$0: restart crashed $service"
    rc-service $s zap start
  else
    log "$0: healed w/o our help $service"
  fi
}

#######################################################################
#
set -u
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(runlevel)" == "N 3" ]]; then
  for s in ssh unbound $(find /etc/init.d -name 'tor*' -print0 | xargs -r -n 1 --null basename); do
    rc-service -qq $s status
    if [[ $? -eq 32 ]]; then
      healService $s &
    fi
  done
fi
