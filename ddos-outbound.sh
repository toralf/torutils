#!/bin/bash
# set -x


# catch tcp v4 exit connections of $state having >= $max connections to the same destination

# could be used to feed:
#
# f=/tmp/ddos-outbound.out; while :; do (/opt/torutils/ddos-outbound.sh syn-sent; /opt/torutils/ddos-outbound.sh time-wait) > $f; if [[ -s $f ]]; then cat $f >> /etc/tor/conf.d/40_reject_auto; /sbin/rc-service tor2 reload; /sbin/rc-service tor reload; fi; rm $f; sleep 30; done


state=${1:-syn-sent}
max=${2:-300}


#######################################################################
set -euf
export LANG=C.utf8

accept=/etc/tor/conf.d/80_accept
reject=/etc/tor/conf.d/40_reject_auto

ts=$(LC_TIME=de date +%c)

/sbin/ss --no-header --tcp --numeric state ${state} -4 |\
# create a hash with "address:port" as the key and "count" as a value
perl -wane '
  BEGIN {
    my $Hist=();
  }
  {
    $Hist{$F[3]}++;
  }
  END {
    foreach my $addr_port (sort { $Hist{$b} <=> $Hist{$a} || $a cmp $b } keys %Hist) {
      my $count = $Hist{$addr_port};
      if ($count >= '"$max"') {
        print $addr_port, " ", $count, "\n";
      }
    }
  } ' |\
# reformat accordingly to the torrc syntax
while read -r line
do
  read -r addr_port count <<< $line
  read -r addr port < <(tr ':' ' '<<< $addr_port)

  if grep -q -F -e " $addr_port " -e " $addr:* " $accept; then
    continue
  fi

  if ! grep -q -F -e " $addr_port " -e " *:$port " $reject; then
    printf "%-s %-7s %-48s # %5i %-10s at %s\n" "ExitPolicy" "reject" "$addr_port" "$count" "$state" "$ts"
  fi
done
