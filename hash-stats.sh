#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# plot timeout values of an iptables hash


set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"


tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

for h in ${@:-/proc/net/ipt_hashlimit/tor-block-443}
do
  awk '{ print $1 }' $h | sort -bn > $tmpfile

  n=$(wc -l < $tmpfile)
  gnuplot -e '
    set terminal dumb 65 24;
    set border back;
    set title "timeout of '$n' ips in '$h'";
    set key noautotitle;
    set xlabel "ip";
    plot "'$tmpfile'" pt "o";
  '
done

rm $tmpfile
