#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# restart a crashed service under Gentoo Linux (OpenRC)

function log() {
  local msg="$*"

  echo "$0 $(date): $msg" >&2
  logger "$msg"
}

function healService() {
  local service=${1?}

  log "crashed: $service"
  sleep 30
  rc-service -qq $service status
  if [[ $? -eq 32 ]]; then
    log "restarting: $service"
    rc-service $service zap start
  else
    log "healed w/o our help: $service"
  fi
}

#######################################################################
#
set -u
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(runlevel)" == "N 3" ]]; then
  for s in unbound ssh $(find /etc/init.d -name 'tor*' -print0 | xargs -r -n 1 --null basename); do
    rc-service -qq $s status
    if [[ $? -eq 32 ]]; then
      healService $s &
    fi
  done
fi
