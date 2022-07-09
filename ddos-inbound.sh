#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port

# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40637

# crontab example:
#
#*/3 * * * * /opt/torutils/ddos-inbound.sh -b
#59  * * * * /opt/torutils/ddos-inbound.sh -u


function block() {
  show |\
  grep "^address" |\
  awk '{ print $2 }' |\
  sort -u -r -n |\
  while read -r s
  do
    if [[ $s =~ ']' ]]; then
      v=6
    else
      v=''
    fi

    if ! ip${v}tables --numeric --list | grep -q "^DROP .* $s "; then
      echo "block $s"
      ip${v}tables -I INPUT -p tcp --source $s -j DROP -m comment --comment "Tor-DDoS"
    fi
  done
}


function unblock()  {
  local max=$(( 3 * limit ))

  for v in '' 6
  do
    /sbin/ip${v}tables -nvL --line-numbers |\
    grep 'Tor-DDoS' |\
    grep -v '[KMG] ' |\
    awk '{ print $1, $2, $9} ' |\
    sort -r -n |\
    while read -r num pkts s
    do
      if [[ $pkts -lt $max ]]; then
        echo "unblock $s"
        /sbin/ip${v}tables -D $num
      fi
    done
  done
}


function show() {
  for relay in $relays
  do
    if [[ $relay =~ ']' ]]; then
      v=6
    else
      v=4
    fi
    ss --no-header --tcp -$v --numeric |\
    grep "^ESTAB .* $(sed -e 's,\[,\\[,g' -e 's,\],\\],g' <<< $relay) " |\
    perl -wane '{
      BEGIN {
        my %h = (); # amount of open ports per address
        my $ip;
      }

      if ('"$v"' == 4)  {
        $ip = (split(/:/, $F[4]))[0];
      } else {
        $ip = (split(/\]/, $F[4]))[0];
        $ip =~ tr/[//d;
      }
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

  echo "block4 $(iptables -nL  | grep -c '^DROP .* Tor-DDoS')"
  echo "block6 $(ip6tables -nL  | grep -c '^DROP .* Tor-DDoS')"
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

action="show"
limit=20    # authorities have a limit of 50
relays=$(grep "^ORPort" /etc/tor/torrc{,2} | awk '{ print $2 }' | sort)

while getopts bl:r:su opt
do
  case $opt in
    b)  action="block" ;;
    l)  limit=$OPTARG ;;
    r)  relays=$OPTARG ;;
    s)  action="show" ;;
    u)  action="unblock" ;;
    *)  echo "unknown parameter '${opt}'"; exit 1;;
  esac
done

$action
