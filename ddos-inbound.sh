#!/bin/bash
# set -x

# catch addresses DDoS'ing the OR port

# https://gitlab.torproject.org/tpo/core/tor/-/issues/40636
# https://gitlab.torproject.org/tpo/core/tor/-/issues/40637

# crontab example:
#
# Tor DDoS
# 0-58 * * * * /opt/torutils/ddos-inbound.sh -b 1>/dev/null
# 59   * * * * /opt/torutils/ddos-inbound.sh -u; /opt/torutils/ddos-inbound.sh -b 1>/dev/null; /opt/torutils/ddos-inbound.sh -v


function block() {
  local curr=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

  for v in '' 6
  do
    ip${v}tables -n -L INPUT > $curr

    _show_v $v |\
    grep "^address${v} " |\
    awk '{ print $2 }' |\
    sort -r -n |\
    while read -r s
    do
      [[ $s =~ '.' ]] && v='' || v='6'
      if ! grep -q "^DROP .* $s .* $tag " $curr; then
        echo "block $s"
        ip${v}tables -I INPUT -p tcp --source $s -j DROP -m comment --comment "$tag limit=$limit"
      fi
    done
  done

  rm $curr
}


function unblock()  {
  local max=$(( 3 * limit ))

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

      if [[ $pkts -le $max ]]; then
        echo -e "unblock $s\t($pkts pkts)"
        ip${v}tables -D INPUT $num
      fi
    done
  done
}


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
        printf "%-35s %15i %4i\n", "relay:'$relay'", $ips, $sum;
      }
    '
  done

  echo "blocked${v} "$(ip${v}tables -n -L INPUT | grep -c "^DROP .* $tag ")
}


function show() {
  for v in '' 6
  do
    _show_v $v
  done
}


# list probably wrongly blocked ips
function verify() {
  local relays=/tmp/relays

  if [[ ! -s $relays || $(( EPOCHSECONDS-$(stat -c %Y $relays) )) -gt 3600 ]]; then
    curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - |\
    jq -cr '.relays[].a' |\
    tr '\[\]" ,' ' ' |\
    xargs -r -n 1 |\
    sort > /tmp/relays
  fi

  for v in '' 6
  do
    ip${v}tables -nv -L INPUT --line-numbers |\
    grep -F "$tag" |\
    grep -F -w -f $relays |\
    awk '{ print $1, $2, $9 }' |\
    sort -u -r -n |\
    while read -r num pkts s
    do
      echo -e "is listed as a relay $s\t($pkts pkts)"
    done
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
