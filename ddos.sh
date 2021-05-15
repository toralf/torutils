#!/bin/bash
# set -x


# catch tcp4 connections of $state having >= $max connections to the same destination

set -euf
export LANG=C.utf8


state=${1:-syn-sent}
max=${2:-300}

#######################################################################

accept=/etc/tor/conf.d/80_accept
reject=/etc/tor/conf.d/40_reject_auto

ts=$(LC_TIME=de date +%c)

/sbin/ss --no-header --tcp --numeric state ${state} -4 |\
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
while read -r line
do
  read -r addr_port count <<< $line
  if grep -q -F -e " $ " $accept; then
    continue
  fi
  read -r addr port < <(tr ':' ' '<<< $addr_port)
  if grep -q -F -e " *:$port " -e " $addr:$port " $accept; then
    printf "%-s %-7s %-48s # %5i %-10s at %s\n" "ExitPolicy" "reject" "$addr_port" "$count" "$state" "$ts"
  fi
done
