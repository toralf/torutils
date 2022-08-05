#!/bin/bash
# set -x


# anonymise/plot about blocked ip addresses (see ipv4-rules.sh and ipv6-rules.sh)


function dump()  {
  ipset list -s $1 |\
  grep ' timeout' |\
  grep -v 'Header' |\
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


# a simple historgram
function plot() {
  local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

  perl -wane '
    BEGIN {
      my %h=();
    }
    {
      $h{$F[0]}++;
    }
    END {
      foreach my $k (sort { $h{$a} <=> $h{$b} || $a cmp $b } keys %h) {
        printf "%4i  %-s\n", $h{$k}, $k;
      }
    }
    ' $1 |\
  perl -wane '
    BEGIN {
      my %h=();
    }
    {
      $h{$F[0]}++;
    }
    END {
      foreach my $k (sort { $a <=> $b } keys %h) {
        printf "%4i  %5i\n", $k, $h{$k}
      }
    }
    ' > $tmpfile

  local xmax=$(tail -n 1 $tmpfile | awk '{ print ($1) }')
  ((xmax++))
  local n=$(sort -u $1 | wc -l)
  local N=$(wc -l < $1)

  gnuplot -e '
    set terminal dumb 90 25;
    set title " '"$n"' ip addresses, '"$N"' entries";
    set xlabel "occurrence of an ip address";
    set ylabel "ip addresses";
    set key noautotitle;
    set xrange [0:'$xmax'];
    set xtics 1;
    plot "'$tmpfile'" with impuls;
    '

  rm $tmpfile
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

while getopts aAdDp: opt
do
  case $opt in
    a)  dump tor-ddos  | anonymise  ;;
    A)  dump tor-ddos6 | anonymise6 ;;
    d)  dump tor-ddos  ;;
    D)  dump tor-ddos6 ;;
    p)  plot $OPTARG ;;
    *)  echo "unknown parameter '$opt'"; exit 1;;
  esac
done
