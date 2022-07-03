#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40637


# quick check:
#
# ddos-inbound.sh | grep "^r"
#
# feed the firewall:
#
# ddos-inbound.sh | grep ^address | awk '{ print $2 }' | sort -u | while read s; do iptables -I INPUT -p tcp --source $s -j DROP; done


set -euf
export LANG=C.utf8

limit=${1:-50}
relays=${2:-$(grep "^ORPort" /etc/tor/torrc{,2} | awk '{ print $2 }' | grep -v -F ']')}

echo -e "limit $limit"

for relay in $relays
do
  echo
  read -r ip orport < <(tr ':' ' ' <<< $relay)
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
      print "relay:'$relay' $ips $conns\n";
    }
  }' |\
  column -t
  echo
done
