#!/bin/sh
#
# set -x

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"


# work on the output of orstatus.py
#   format:
#   reason        fingerprint                                 address       port ip version
#
#   IOERROR       069E732EC96774ED5609D4803D7B1130E338B0EB    94.19.14.183  9001 v4 0.3.2.7-rc

cat $* |\

perl -we '
  my %h_reason = ();

  while (<>) {
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
  ' |\

# this file contains the fingerprints versus their counts of STATUS
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
#   417 nodes are fine. 1065 had 1 ioerror, 355 had 2 ioerrors, ...
#
perl -we '
  my %h_ioerror = ();

  while (<>) {
    chomp();
    s/^\s+//g;

    my ($fingerprint, $ioerror, $timeout, $connectreset, $done) = split();

    # currently we are only interested in ioerrors
    #
    $h_ioerror{$ioerror}++;
  }

  foreach my $key (sort { $a <=> $b } keys %h_ioerror) {
    print $key, "\t", $h_ioerror{$key}, "\n";
  }
  ' > histogram

wc -l $* fingerprints histogram

# plot the content of "histogram" (contains only io errors)
#
gnuplot -e '
  set logscale y 10;
  set logscale x 10;
  set xlabel "ioerrors";
  set ylabel "relays";
  set style line 1 lc rgb "#0060ad" lt 1 lw 1 pt 7 ps 1.5;

  plot "histogram" with linespoints ls 1;
  pause(-1);
  '
