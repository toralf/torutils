#!/bin/bash
# set -x

# catch # of ip address with unusual high number of inbound connections to the OR port

set -euf
export LANG=C.utf8

limit=${1:-50}
orports=${2:-"443 9001"}
address="65.21.94.13"

echo -e "limit=$limit"

for orport in $orports
do
  echo -e "\nORPort $orport"
  ss --tcp -n |\
  grep "^ESTAB" |\
  grep " $address:$orport " |\
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
        if ($h{$ip} > '"'$limit'"') {
          $ips++;
          $conns += $h{$ip};
          print "$ip $h{$ip}\n";
        }
      }
      print "ips $ips\nconns $conns\n";
    }
  }' |\
  column -t
done
