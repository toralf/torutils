#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# dumpIpset ip addresses of ipset(s) -or- plot histograms of that

# kick off the header of the ipset
function dumpIpset() {
  ipset list -s $1 |
    sed -e '1,8d'
}

# 1.2.3.4 -> 1.2.3.0/24
function anonymiseIp() {
  awk '{ print $1 }' |
    sed -e "s,\.[0-9]*$,.0/24,"
}

# 1:2:3:4:5:6:7:8 -> 0001:0002:0003:0004:0005::/80
function anonymiseIp6() {
  awk '{ print $1 }' |
    $(dirname $0)/expand_v6.py |
    cut -f1-5 -d ':' |
    sed -e "s,$,::/80,"
}

# plot a histogram about ip address occurrences within ipset dump
function plotIpOccurrences() {
  local files=$*

  local N
  if ! N=$(wc -l < <(cat $files)); then
    echo " no files given" >&2
    return 1
  fi
  if [[ $N -eq 0 ]]; then
    echo " no input data" >&2
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
  awk '{ print $1 }' $files | sort | uniq -c | sort -bn | awk '{ print $1 }' | uniq -c | awk '{ print $2, $1 }' >$tmpfile

  echo "hits ips"
  if [[ $(wc -l <$tmpfile) -gt 7 ]]; then
    head -n 3 $tmpfile
    echo '...'
    tail -n 3 $tmpfile
  else
    cat $tmpfile
  fi

  if [[ $(wc -l <$tmpfile) -gt 1 ]]; then
    local n
    n=$(awk '{ print $1 }' $files | sort -u | wc -l)
    gnuplot -e '
        set terminal dumb 65 24;
        set border back;
        set title "'"$N"' hits of '"$n"' ips";
        set key noautotitle;
        set xlabel "hit";
        set logscale y 2;
        plot "'$tmpfile'" pt "o";
    '
  else
    echo
  fi

  rm $tmpfile
}

function plotTimeoutValues() {
  local tmpfile
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
  dumpIpset "$1" | awk '{ print $3 }' | sort -bn >$tmpfile

  local N
  N=$(wc -l <$tmpfile)

  if [[ $N -gt 7 ]]; then
    gnuplot -e '
        set terminal dumb 65 24;
        set border back;
        set title "'$N' timeout values in '$1'";
        set key noautotitle;
        set yrange [0:*];
        plot "'$tmpfile'" pt "o";'
  else
    cat $tmpfile
  fi

  rm $tmpfile
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

while getopts aAdDptT opt; do
  shift || true # OPTARG is optional
  case $opt in
  a) dumpIpset ${1:-tor-ddos-443} | anonymiseIp ;;
  A) dumpIpset ${1:-tor-ddos6-443} | anonymiseIp6 ;;
  d) dumpIpset ${1:-tor-ddos-443} ;;
  D) dumpIpset ${1:-tor-ddos6-443} ;;
  p) plotIpOccurrences $@ ;;
  t) plotTimeoutValues ${1:-tor-ddos-443} ;;
  T) plotTimeoutValues ${1:-tor-ddos6-443} ;;
  *)
    echo "unknown parameter '$opt'"
    exit 1
    ;;
  esac
done
