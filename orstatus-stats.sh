#!/bin/bash
# set -x


# create from input files a histogram like:
#     0       417
#     1       1065
#     2       355
#
# read it as:
#   417 nodes had 0 <reason>, 1065 had 1 <reason>, 355 had 2 <reason>, ...


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

reason=${1?reason needed}
shift
[[ $# -gt 0 ]]

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
grep -h "^$reason " $* |\
awk '{ print $2 }' | sort     | uniq -c |\
awk '{ print $1 }' | sort -bn | uniq -c |\
awk '{ print $2, $1 }' | tee $tmpfile

xmax=$(tail -n 1 $tmpfile | awk '{ print $1 }')
(( xmax = xmax + 2))

gnuplot -e '
  set terminal dumb;
  set title "fingerprints";
  set key noautotitle;
  set xlabel "ioerrors";
  set xrange [-0.5:'"$xmax"'];
  set yrange [0.5:*];
  set logscale y 10;
  plot "'$tmpfile'" pt "o";
  '

rm $tmpfile
