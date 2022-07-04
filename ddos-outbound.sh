#!/bin/bash
# set -x


# catch tcp v4 exit connections of $state having >= $max connections to the same destination


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

state=${1:-syn-sent}
max=${2:-300}

accept=/etc/tor/conf.d/80_accept
reject=/etc/tor/conf.d/40_reject_auto

ts=$(LC_TIME=de date +%c)

ss --no-header --tcp -4 --numeric state ${state} |\
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
