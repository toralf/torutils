#!/bin/bash
# set -x


# catch tcp connections of $state having >= $max connections to the same destination

set -euf
export LANG=C.utf8


state=${1:-syn-sent}
max=${2:-300}

#######################################################################

accept=/etc/tor/conf.d/80_accept
reject=/etc/tor/conf.d/40_reject_auto


ts=$(LC_TIME=de date +%c)

/sbin/ss --no-header --tcp --numeric state ${state} |\
perl -wane '
  BEGIN {
    my $Hist=();
  }
  {
    $Hist{$F[3]}++;
  }
  END {
    my $tm = scalar localtime(time());

    foreach my $tupel (sort { $Hist{$b} <=> $Hist{$a} || $a cmp $b } keys %Hist) {
      my $count = $Hist{$tupel};
      if ($count >= '"$max"') {
        print $tupel, " ", $count, "\n";
      }
    }
  } ' |\
while read -r line
do
  read -r tupel count <<< $line
  if grep -q -F -e " $tupel " $accept; then
    continue
  fi
  addr=$(cut -f1 -d':' -s <<< $tupel)
  port=$(cut -f2 -d':' -s <<< $tupel)
  if grep -q -F -e " *:$port " -e " $addr:$port " $accept; then
    [[ $tupel =~ '[' ]] && rej="reject6" || rej="reject"
    printf "%-s %-7s %-48s # %5i %-10s at %s\n" "ExitPolicy" "$rej" "$tupel" "$count" "$state" "$ts"
  fi
done
