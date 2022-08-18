#!/bin/bash
# set -x


# dump and plot hostograms about occurrence of ip addresses in ipset(s)

function dump()  {
  ipset list -s $1 |\
  sed -e '1,8d' |\
  awk '{ print $1 }'
}


# 1.2.3.4 -> 1.2.3.0/24
function anonymise()  {
  sed -e "s,\.[0-9]*$,.0/24,"
}


# 2000::23:42 -> 2000::/64
function anonymise6()  {
  /opt/torutils/expand_v6.py |\
  cut -c1-19 |\
  sed -e "s,$,::/64,"
}


# a simple histogram
function plot() {
  local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

  sort | uniq -c | sort -bn | awk '{ print $1 }' | uniq -c | awk '{ print $2, $1 }' > $tmpfile

  gnuplot -e '
    set terminal dumb 65 24;
    set border back;
    set title "'"$N"' occurrences of '"$n"' ip addresses";
    set key noautotitle;
    set xlabel "occurrence";
    set logscale y 2;
    plot "'$tmpfile'" pt "o";
  '

  rm $tmpfile
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

set -o pipefail

while getopts aAdDp opt
do
  shift
  case $opt in
    a)  dump ${1:-tor-ddos}  | anonymise  | uniq -c ;;
    A)  dump ${1:-tor-ddos6} | anonymise6 | uniq -c ;;
    d)  dump ${1:-tor-ddos}  ;;
    D)  dump ${1:-tor-ddos6} ;;
    p)  [[ $# -gt 0 ]]; N=$(cat $* | wc -l); n=$(cat $* | sort -u | wc -l); cat $* | plot ;;
    *)  echo "unknown parameter '$opt'"; exit 1 ;;
  esac
done
