#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port

# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40637


function _show_v() {
  for relay in $relays
  do
    if [[ $relay =~ '.' ]]; then
      if [[ "$v" = "6" ]]; then
        continue
      fi
    else
      if [[ "$v" = "" ]]; then
        continue
      fi
    fi

    ss --no-header --tcp -${v:-4} --numeric |\
    grep "^ESTAB .* $(sed -e 's,\[,\\[,g' -e 's,\],\\],g' <<< $relay) " |\
    perl -wane '
      BEGIN {
        my $ip = undef;
        my %h = ();
      }

      if ("'$v'" eq "6")  {
        $ip = (split(/\]/, $F[4]))[0];
        $ip =~ tr/[//d;
      } else {
        $ip = (split(/:/, $F[4]))[0];
      }
      $h{$ip}++;

      END {
        my $ips = 0;
        my $sum = 0;
        foreach my $ip (sort { $h{$a} <=> $h{$b} || $a cmp $b } grep { $h{$_} > '$limit' } keys %h) {
          $ips++;
          my $conns = $h{$ip};
          $sum += $conns;
          printf "%-35s %15s %4i\n", "address'$v'", $ip, $conns;
        }
        printf "%-35s %15i %4i\n\n", "relay:'$relay'", $ips, $sum;
      }
    '
  done
}


function show() {
  for v in '' 6
  do
    _show_v $v
  done
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

action="show"
limit=20
relays=$(grep "^ORPort" /etc/tor/torrc{,2} 2>/dev/null | awk '{ print $2 }' | sort)

while getopts bl:r:st:uv opt
do
  case $opt in
    l)  limit=$OPTARG ;;
    r)  relays=$OPTARG ;;
    s)  action="show" ;;
    t)  tag=$OPTARG ;;
    *)  echo "unknown parameter '$opt'"; exit 1;;
  esac
done

$action
