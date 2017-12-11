#!/bin/sh
#
#set -x

# work on the output of err.py
# got eg. by: nohup bash -c "./err.py --ctrlport 9051 &> err.$(date +%Y%m%d-%H%M%S).tor" &

# sort fingerprints by their amounts of ioerrors
#
# input file has this format :
#   3196   256  2734  1512928870 Sun Dec 10 19:01:10 2017 ED4B112B...   209.141.36.42  9001 us nick
#
perl -we '
  my %h = ();

  while (<>) {
    @line = split();
    $h{$line[9]}++;
  }

  foreach $key (sort { $h{$b} <=> $h{$a} } keys %h) {
    print $key, "\t", $h{$key}, "\n";
  }
  ' err* |\
tee fingerprints |\

# create a histogram over count values
# output will look like:
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
  set xrange [0:50];
  set yrange [0:];
  set xlabel "ioerrors";
  set ylabel "relays";
  set style line 1 lc rgb "#0060ad" lt 1 lw 1 pt 7 ps 1.5;

  plot "histogram" with linespoints ls 1;
  pause -1;
  '
