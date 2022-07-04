#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port

# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40637


function feedFirewall() {
  local i=0

  while read -r s
  do
    # insert it before all other rules
    iptables -I INPUT -p tcp --source $s -j DROP
    (( ++i ))
  done < <(
    showConnections |\
    grep "^address" |\
    awk '{ print $2 }' |\
    sort -u
  )

  if [[ $i -gt 0 ]]; then
    echo " $(basename $0): added $i rules"
  fi
}


function showConnections() {
  for relay in $relays
  do
    ss --no-header --tcp -4 --numeric |\
    grep "^ESTAB .* $relay " |\
    perl -wane '{
      BEGIN {
        my %h = (); # amount of open ports per address
      }

      my ($ip, $port) = split(/:/, $F[4]);
      $h{$ip}++;

      END {
        my $ips = 0;
        my $sum = 0;
        foreach my $ip (sort { $h{$a} <=> $h{$b} || $a cmp $b } grep { $h{$_} > '"$limit"' } keys %h) {
          $ips++;
          my $conn = $h{$ip};
          $sum += $conn;
          print "address $ip $conn\n";
        }
        print "relay:'"$relay"' $ips $sum\n";
      }
    }'
  done
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=20
relays=$(grep "^ORPort" /etc/tor/torrc{,2} | awk '{ print $2 }' | grep -v -F ']')

if [[ $# -eq 0 ]]; then
  showConnections | grep "^r" | column -t
  exit 0
fi

while getopts fl:r:s opt
do
  case $opt in
    f)  feedFirewall ;;
    l)  limit=$OPTARG ;;
    r)  relays=$OPTARG ;;
    s)  showConnections ;;
    *)  echo "unknown parameter '${opt}'"; exit 1;;
  esac
done
