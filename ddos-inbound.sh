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
  grep "^address " |\
  awk '{ print $2 }' |\
  sort -u -r -n |\
  while read -r s
  do
    [[ $s =~ ']' ]] && v=6 || v=''
    if ! ip${v}tables -n -L INPUT | grep -q "^DROP .* $s .* $tag "; then
      echo "block $s"
      ip${v}tables -I INPUT -p tcp --source $s -j DROP -m comment --comment "$tag"
    fi
  done
}


function unblock()  {
  local max=50      # current consensus limit

  for v in '' 6
  do
    ip${v}tables -nv -L INPUT --line-numbers |\
    grep -F " $tag " |\
    awk '{ print $1, $2, $9} ' |\
    sort -r -n |\
    while read -r num pkts s
    do
      if [[ $pkts =~ "K" || $pkts =~ "M" || $pkts =~ "G" ]]; then
        continue
      fi

      if [[ $pkts -lt $max ]]; then
        echo -e "unblock $s\t($pkts hits)"
        ip${v}tables -D INPUT $num
      fi
    done
  done
}


function show() {
  for relay in $relays
  do
    [[ $relay =~ ']' ]] && v=6 || v=''

    if [[ $v = "6" ]]; then
      ss --no-header --tcp -6 --numeric
    else
      ss --no-header --tcp -4 --numeric
    fi |\
    grep "^ESTAB .* $(sed -e 's,\[,\\[,g' -e 's,\],\\],g' <<< $relay) " |\
    perl -wane '
      BEGIN {
        my $ip;
        my %h;
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
          my $conn = $h{$ip};
          $sum += $conn;
          print "address $ip $conn\n";
        }
        print "relay:'"$relay"' $ips $sum\n";
      }
    '
  done

  for v in '' 6
  do
    echo "blocked${v} "$(ip${v}tables -n -L INPUT | grep -c "^DROP .* $tag ")
  done
}


# list probably wrongly blocked ips
function verify() {
  local torlist=/tmp/torlist

  # download is restricted to 1x within 30 min
  if [[ ! -s $torlist || $(( EPOCHSECONDS-$(stat -c %Y $torlist) )) -gt 86400 ]]; then
    (
      curl -s -0 https://www.dan.me.uk/torlist/
      dig +short snowflake-01.torproject.net.
      dig +short snowflake-01.torproject.net. -t aaaa
    ) |\
    # 1.2.3.4 != 1.2.3.45
    sed -e 's,^, ,' -e 's,$, ,' > $torlist
  fi

  for v in '' 6
  do
    ip${v}tables -nv -L INPUT --line-numbers |\
    grep -F "$tag" |\
    grep -F -f $torlist
  done
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

action="show"
limit=20
relays=$(grep "^ORPort" /etc/tor/torrc{,2} 2>/dev/null | awk '{ print $2 }' | sort)
tag="Tor-DDoS"

while getopts bl:r:st:uv opt
do
  case $opt in
    b)  action="block" ;;
    l)  limit=$OPTARG ;;
    r)  relays=$OPTARG ;;
    s)  action="show" ;;
    t)  tag=$OPTARG ;;
    u)  action="unblock" ;;
    v)  action="verify" ;;
    *)  echo "unknown parameter '$opt'"; exit 1;;
  esac
done

$action
