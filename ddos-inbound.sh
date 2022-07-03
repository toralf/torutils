#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636

set -euf
export LANG=C.utf8

limit=${1:-50}
relays=${2:-"65.21.94.13:443 65.21.94.13:9001"}

echo -e "limit $limit"

for relay in $relays
do
  read -r ip orport < <(tr ':' ' ' <<< $relay)
  echo -e "\nrelay $relay"
  ss --tcp -n |\
  grep "^ESTAB" |\
  grep " $relay " |\
  perl -wane '{
    BEGIN {
      my %h = (); # port count per ip address
    }

    my ($ip, $port) = split(/:/, $F[4]);
    $h{$ip}++;

    END {
      $ips = 0;
      $conns = 0;
      foreach my $ip (sort { $h{$a} <=> $h{$b} || $a cmp $b } keys %h) {
        if ($h{$ip} > '$limit') {
          $ips++;
          $conns += $h{$ip};
          print "address $ip $h{$ip}\n";
        }
      }
      print "or:'$orport' $ips $conns\n";
    }
  }' |\
  column -t
done
