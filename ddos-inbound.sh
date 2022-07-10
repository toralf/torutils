#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port

# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40637

# crontab example:
#
#*/3 * * * * /opt/torutils/ddos-inbound.sh -b
#58  * * * * /opt/torutils/ddos-inbound.sh -v
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
      ip${v}tables -I INPUT -p tcp --source $s -j DROP -m comment --comment "$fwcomment"
    fi
  done
}


function unblock()  {
  local max=50      # current consensus limit

  for v in '' 6
  do
    /sbin/ip${v}tables -nvL --line-numbers |\
    grep -F "$fwcomment" |\
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

  echo "block4 "$(iptables  -nL | grep -c "^DROP .* $fwcomment")
  echo "block6 "$(ip6tables -nL | grep -c "^DROP .* $fwcomment")
}


# check that no Tor relay was blocked (they assumed to be right)
function verify() {
  local torlist=/tmp/torlist

  # download is restricted to 1x within 30 min
  if [[ ! -s $torlist || $(( EPOCHSECONDS-$(stat -c %Y $torlist) )) -gt 86400 ]]; then
    curl -0 https://www.dan.me.uk/torlist/ -o $torlist
    # 1.2.3.4 != 1.2.3.45
    sed -i -e 's,^, ,' -e 's,$, ,' $torlist
  fi

  for v in '' 6
  do
    /sbin/ip${v}tables -nvL --line-numbers |\
    grep -F "$fwcomment" |\
    grep -F -f $torlist
  done
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

action="show"
limit=20
relays=$(grep "^ORPort" /etc/tor/torrc{,2} | awk '{ print $2 }' | sort)
fwcomment="Tor-DDoS"

while getopts bl:r:suv opt
do
  case $opt in
    b)  action="block" ;;
    l)  limit=$OPTARG ;;
    r)  relays=$OPTARG ;;
    s)  action="show" ;;
    u)  action="unblock" ;;
    v)  action="verify" ;;
    *)  echo "unknown parameter '${opt}'"; exit 1;;
  esac
done

$action
