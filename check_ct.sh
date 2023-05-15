#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# check conntrack table statistics for relevant issues and print them if new/changed

set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

if [[ ! -x "$(command -v conntrack)" ]]; then
  exit 1
fi

tmpfile=/tmp/conntrack.txt
if [[ ! -f $tmpfile.old ]]; then
  touch $tmpfile.old
fi

conntrack -S | grep -v ' insert_failed=0 drop=0 ' | awk '{ print $1, $5, $6 }' | cut -f2- -d':' >$tmpfile
n=$(conntrack -C)
if [[ $n -gt 50000 ]]; then
  echo "more than 50K in conntrack table: $n" >>$tmpfile
fi

if ! diff -q $tmpfile{,.old} &>/dev/null; then
  tail -v $tmpfile{,.old}
  cp $tmpfile $tmpfile.old
fi
