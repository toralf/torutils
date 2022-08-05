#!/bin/sh
#
# set -x

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"


[[ -s $1 ]]
tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

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

# this stream contains the fingerprints versus their counts of STATUS
#
#   format:
#   ABCD1234     8     6     0     0
#
# create from that a histogram:
#     0       417
#     1       1065
#     2       355
#
# read it as:
#   417 nodes are fine. 1065 had 1 ioerror, 355 had 2 ioerrors, ...

perl -wane '
  BEGIN {
    my %h_ioerror = ();
  }
  {
    chomp();
    s/^\s+//g;

    my ($fingerprint, $ioerror, $timeout, $connectreset, $done) = split();

    # currently we are only interested in ioerrors
    #
    $h_ioerror{$ioerror}++;
  }
  END {
    foreach my $key (sort { $a <=> $b } keys %h_ioerror) {
      print $key, "\t", $h_ioerror{$key}, "\n";
    }
  }' > $tmpfile

# "$tmpfile" contains only the io errors
#
gnuplot -e '
  set terminal dumb 90 25;
  set xlabel "ioerrors";
  set ylabel "relays";
  set key noautotitle;
  set logscale y 10;

  plot "'$tmpfile'" with impuls;
  '

rm $tmpfile
