#!/bin/sh
#
# set -x

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"


[[ -s $1 ]]
tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)


# this creates the fingerprints versus their reasons IOERROR TIMEOUT CONNECTRESET DONE
#
#   format:
#   ABCD1234     8     6     0     0
perl -wane '
  BEGIN {
    my %h_reason = ();
  }
  {
    chomp();
    s/^\s+//g;

    my ($reason, $fingerprint) = split(/\s+/);
    if (! exists $h_reason{$fingerprint}) {
      $h_reason{$fingerprint} = {
        "DONE"          => 0,
        "IOERROR"       => 0,
        "TIMEOUT"       => 0,
        "CONNECTRESET"  => 0,
      };
    }
    $h_reason{$fingerprint}->{$reason}++;
  }
  END {
    # sorted output
    #
    foreach my $key (sort {     $h_reason{$b}->{"IOERROR"}       <=> $h_reason{$a}->{"IOERROR"}
                            or  $h_reason{$b}->{"TIMEOUT"}       <=> $h_reason{$a}->{"TIMEOUT"}
                            or  $h_reason{$b}->{"CONNECTRESET"}  <=> $h_reason{$a}->{"CONNECTRESET"}
                            or  $h_reason{$b}->{"DONE"}          <=> $h_reason{$a}->{"DONE"}
                          } keys %h_reason) {
      printf ("%s", $key);
      foreach my $reason ( qw/IOERROR TIMEOUT CONNECTRESET DONE/ )  {
        printf (" %5i", $h_reason{$key}->{$reason});
      }
      print "\n";
    }
  }' $1 |\

# currently we are only interested in ioerrors
# create from the stream above a histogram:
#     0       417
#     1       1065
#     2       355
#
# read it as:
#   417 nodes are fine. 1065 had 1 ioerror, 355 had 2 ioerrors, ...
awk '{ print $2 }' |\
sort | uniq -c | awk ' { print $2, $1 }' > $tmpfile

xmax=$(tail -n 1 $tmpfile | awk '{ print $1 }')
((xmax++))

gnuplot -e '
  set terminal dumb 90 25;
  set xlabel "ioerrors";
  set title "relays";
  set key noautotitle;
  set logscale y 10;
  set xrange [-1:'$xmax'];
  plot "'$tmpfile'" pt "o";
  '

rm $tmpfile
