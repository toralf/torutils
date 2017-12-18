#!/bin/sh
#
# set -x

# work on the output of err.py
#   format:
#   event         fingerprint                                 address       port version
#
#   IOERROR       069E732EC96774ED5609D4803D7B1130E338B0EB    94.19.14.183  9001 v4

cat $* |\

perl -we '
  my %h = ();

  while (<>) {
    chomp();
    s/^\s+//g;

    my ($event, $fingerprint) = split(/\s+/);
    if (! exists $h{$fingerprint}) {
      $h{$fingerprint} = {
        "DONE"          => 0,
        "IOERROR"       => 0,
        "TIMEOUT"       => 0,
        "CONNECTRESET"  => 0,
      };
    }
    $h{$fingerprint}->{$event}++;
  }

  # sorted output
  #
  foreach my $key (sort {     $h{$b}->{"DONE"}          <=> $h{$a}->{"DONE"}
                          or  $h{$b}->{"IOERROR"}       <=> $h{$a}->{"IOERROR"}
                          or  $h{$b}->{"TIMEOUT"}       <=> $h{$a}->{"TIMEOUT"}
                          or  $h{$b}->{"CONNECTRESET"}  <=> $h{$a}->{"CONNECTRESET"}
                        } keys %h) {
    printf ("%s", $key);
    foreach my $event ( qw/DONE IOERROR TIMEOUT CONNECTRESET/ )  {
      printf (" %5i", $h{$key}->{$event});
    }
    print "\n";
  }
  ' |\

# this file contains the fingerprints versus their counts
#
#   format:
#   ABCD1234     8     6     0     0
#
tee fingerprints |\

# create a histogram of the
#   format:
#     0       417
#     1       1065
#     2       355
#
# read this as:
#   417 nodes are fine. 1065 had 1 ioerror, 355 had 2, ...
#
perl -we '
  my %h = ();

  while (<>) {
    chomp();
    my ($fingerprint, undef, $ioerror) = split();
    $h{$ioerror}++
  }

  foreach my $key (sort { $a <=> $b } keys %h) {
    print $key, "\t", $h{$key}, "\n";
  }
  ' > histogram

# plot the histogram
#
gnuplot -e '
  if (0) {
    set logscale x 10;
  }
  if (1) {
    set logscale y 10;
  }

  set xlabel "ioerrors";
  set ylabel "relays";
  set style line 1 lc rgb "#0060ad" lt 1 lw 1 pt 7 ps 1.5;

  plot "histogram" with linespoints ls 1;
  pause(-1);
  '

wc -l $* fingerprints histogram

