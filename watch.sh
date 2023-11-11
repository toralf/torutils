#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

log=$1 # logfile to watch
pat=$2 # pattern file for grep
shift 2
opt="$*" # options for grep

mailto="tor-relay@zwiebeltoralf.de"

while :; do
  if catched=$(
    tail --quiet -n 0 -f $log |
      grep -m 1 -f $pat $opt
  ); then
    if [[ -n $catched ]]; then
      tail -n 50 $log | mail -s "$(basename $log)  $(cut -c 1-180 <<<$catched)" --end-options $mailto &
    else
      echo "failure: $*" | mail -s "$(basename $log)" --end-options $mailto &
    fi
    sleep 60
  else
    # maybe log file rotation
    sleep 5
  fi
done
