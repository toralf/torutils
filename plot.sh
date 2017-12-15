#!/bin/sh
#
# set -x

# work on the output of err.py
#   format:
#   513193091 IOERROR         8DA235C46D5AFC41058FA368F5CF8C4EC7539B1F     77.27.140.228  20576  v4  es  flymylittlepretties

cat $* |\

perl -we '
  my %h = ();

  while (<>) {
    @line = split(/\s+/);
    $h{$line[2]}++;
  }

  foreach $key (sort { $h{$b} <=> $h{$a} } keys %h) {
    print $key, "\t", $h{$key}, "\n";
  }
  ' |\

# this file contains the fingerprints versus their counts
#   format:
#   5F276A6F7AA74AFB2AF100EADA28C7A6F48BA50F        24
#
tee fingerprints |\

# create a histogram over the count values only
#   format:
#   1       1222
#   2       702
#   3       245
#   4       77
#   5       31
#   6       36

perl -we '
  my %h = ();

  while (<>) {
    chomp();
    my ($fingerprint, $count) = split();
    $h{$count}++
  }

  foreach $key (sort { $a <=> $b } keys %h) {
    print $key, "\t", $h{$key}, "\n";
  }
  ' > histogram

# display the histogram
#
gnuplot -e '
  set logscale x 10;
  set logscale y 10;
  set xlabel "ioerrors";
  set ylabel "relays";
  set style line 1 lc rgb "#0060ad" lt 1 lw 1 pt 7 ps 1.5;

  plot "histogram" with linespoints ls 1;
  pause -1;
  '
