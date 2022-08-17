#!/bin/bash
# set -x


# work on output of orstatus.py, eg.:
#
# $> orstatus.py --ctrlport 29051 >> /tmp/orstatus.29051 &
#
# wait a while
#
# $> orstatus-stats.sh /tmp/orstatus.29051
#     146 CONNECTRESET
#     337 DONE
#     539 IOERROR
#       1 NOROUTE
#      36 TIMEOUT
#     137 TLS_ERROR
#
# plot a histogram:
#
# $>  orstatus-stats.sh /tmp/orstatus.29051 TIMEOUT


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

files=""
reason=""
for opt in $*
do
  if [[ -e $opt ]]; then
    files+=" $opt"
  else
    reason=$opt
  fi
done

[[ -n $files ]]

if [[ -z $reason ]]; then
  # just count reasons
  awk '{ print $1 }' $files | sort | uniq -c
else
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
  grep -h "^$reason " $files |\
  awk '{ print $2 }' | sort     | uniq -c |\
  awk '{ print $1 }' | sort -bn | uniq -c |\
  awk '{ print $2, $1 }' > $tmpfile

  m=$(grep -hc "^$reason " $files)
  n=$(grep -h  "^$reason " $files | awk '{ print $2 }' | sort -u | wc -l)

  gnuplot -e '
    set terminal dumb;
    set border back;
    set title "'"$m x $reason"' for '"$n"' fingerprint(s)";
    set key noautotitle;
    set xlabel "'"$reason"'";
    set logscale y 10;
    plot "'$tmpfile'" pt "o";
    '

  rm $tmpfile
fi
