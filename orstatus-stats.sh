#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# work on output of orstatus.py, eg.: plot a histogram for specific event reason:
#
#   orstatus.py --address ::1 --ctrlport 29051 >> /tmp/orstatus.29051 &
#   sleep 3600
#   orstatus-stats.sh /tmp/orstatus.29051 IOERROR


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

files=""
reason=""
for opt in "$@"
do
  if [[ -e $opt ]]; then
    files+=" $opt"
  else
    reason=$opt
  fi
done

if [[ -z $files ]]; then
  echo " no files ?!"
  exit 1
fi

# count per reason
awk '{ print $2 }' $files | sort | uniq -c |
perl -wane 'BEGIN { $sum = 0 } { $sum += $F[0]; print } END { printf("%7i\n", $sum) }'

if [[ -n $reason ]]; then
  # plot for given reason
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
  grep -h " $reason " $files |
  awk '{ print $3 }' | sort     | uniq -c |
  awk '{ print $1 }' | sort -bn | uniq -c |
  awk '{ print $1, $2 }' |\
  tac > $tmpfile

  echo
  echo "fingerprint(s) x $reason"
  lines=$(wc -l < $tmpfile)
  if [[ $lines -gt 7 ]]; then
    head -n 3 $tmpfile
    echo '...'
    tail -n 3 $tmpfile
  else
    cat $tmpfile
  fi

  if [[ $lines -gt 1 ]]; then
    m=$(grep -hc " $reason " $files)
    n=$(grep -h  " $reason " $files | awk '{ print $1 }' | sort -u | wc -l)

    gnuplot -e '
      set terminal dumb;
      set border back;
      set title "'"$n"' fingerprint(s) closing '"$m with $reason"'";
      set key noautotitle;
      set xlabel "fingerprints";
      set logscale x 10;
      set logscale y 2;
      plot "'$tmpfile'" pt "o";
      '
  fi

  rm $tmpfile
fi
