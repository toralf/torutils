#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# restart a crashed service under Gentoo Linux (OpenRC)


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

while :
do
  if [[ "$(runlevel)" = "N 3" ]]; then
    for s in ssh tor tor2
    do
      rc-service -qq $s status
      if [[ $? -eq 32 ]]; then
        echo "$0: restart crashed $s"
        rc-service $s zap start
      fi
    done
  fi
  sleep 10
done
