#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# dump ip addresses of ipset(s) -or- plot histograms of that


# eg. using this crontab entry for 2 local relays running at 443 and 9001:
#
# Tor DDoS stats
# @reboot       curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - | jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | xargs -n 1 | sort -u > /tmp/relays
# */30 * * * *  for p in 443 9001; do d=$(date +\%H-\%M); /opt/torutils/ipset-stats.sh -d tor-ddos-$p | tee -a /tmp/ipset4-$p.txt  > /tmp/ipset4-$p.$d.txt; done
# 1,31 * * * *  for p in 443 9001; do sort -u /tmp/ipset4-$p.*.txt > /tmp/x; grep -h -w -f /tmp/x /tmp/relays > /tmp/y; grep -h -w -f /tmp/y /tmp/ipset4-$p.*.txt | sort | uniq -c | sort -bn > /tmp/z; cp /tmp/z /tmp/blocked_relays-$p; done; rm /tmp/{x,y,z}
#
# run after some time: ipset-stats.sh -p /tmp/ipset4-9*.*.txt


function dump()  {
  ipset list -s $1 |
  sed -e '1,8d' |
  awk '{ print $1 }'
}


# 1.2.3.4 -> 1.2.3.0/24
function anonymise()  {
  sed -e "s,\.[0-9]*$,.0/24,"
}


# eg. if an /48 net is assigned to a v6 relay then 1::2 -> 0001:0000:0000:0000:0000:0000:0000:0002:/128
function anonymise6()  {
  $(basename $0)/expand_v6.py |
  cut -c1-24 |
  sed -e "s,$,::/128,"
}


# plot a histogram (if enough lines are available)
function plot() {
  local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

  sort | uniq -c | sort -bn | awk '{ print $1 }' | uniq -c | awk '{ print $2, $1 }' > $tmpfile

  echo "hits ips"
  if [[ $(wc -l < $tmpfile) -gt 7 ]]; then
    head -n 3 $tmpfile
    echo '...'
    tail -n 3 $tmpfile
  else
    cat $tmpfile
  fi

  if [[ $(wc -l < $tmpfile) -gt 1 ]]; then
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


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

while getopts aAdDp opt
do
  # $2 -if set- is the ipset name
  shift
  case $opt in
    a)  dump ${1:-tor-ddos-443}  | anonymise  | uniq -c ;;
    A)  dump ${1:-tor-ddos6-443} | anonymise6 | uniq -c ;;
    d)  dump ${1:-tor-ddos-443}  ;;
    D)  dump ${1:-tor-ddos6-443} ;;
    p)  [[ $# -gt 0 ]]; N=$(cat "$@" | wc -l); [[ $N -gt 0 ]]; n=$(cat "$@" | sort -u | wc -l); cat "$@"| plot ;;
    *)  echo "unknown parameter '$opt'"; exit 1 ;;
  esac
done
