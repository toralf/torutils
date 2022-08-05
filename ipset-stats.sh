#!/bin/bash
# set -x


# anonymise/plot about blocked ip addresses (ipv4-rules.sh and ipv6-rules.sh)


function dump()  {
  ipset list -s tor-ddos${version} |\
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


function plot() {
  local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

  perl -wane '
    BEGIN {
      my %h=();
    }

    {
      chomp();
      $h{$F[0]}++;
    }
    END {
      foreach my $k (sort { $h{$a} <=> $h{$b} || $a cmp $b } keys %h) {
        printf "%3i   %-s\n", $h{$k}, $k;
      }
    }
    ' $1 |\
  perl -wane '
    BEGIN {
      my %h=();
    }
    {
      chomp();
      $h{$F[0]}++;
    }
    END {
      foreach my $k (sort { $a <=> $b } keys %h) {
        printf "%3i  %2i\n", $k, $h{$k}
      }
    }
    ' |\
    tee $tmpfile

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
      plot "'$tmpfile'" with impuls;
      '
  rm $tmpfile
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

version=""    # empty = IPv4, "6" for IPv6
while getopts adp:v: opt
do
  case $opt in
    a)  dump | anonymise${version} ;;
    d)  dump;;
    p)  plot $OPTARG;;
    v)  version=$OPTARG ;;
    *)  echo "unknown parameter '$opt'"; exit 1;;
  esac
done
