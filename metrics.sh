#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# use node_exporter's "textfile" feature to pump metrics into Prometheus
# https://prometheus.io/docs/instrumenting/exposition_formats/


function _histogram()  {
  perl -wane '
    BEGIN {
      @arr = (0) x 24;  # 0-23 hour
      $inf = 0;         # anything above
      $sum = 0;
    }
    {
      chomp();
      my $hour = int(($F[0]-1)/3600);
      if ($hour <= 23)  {
        $arr[$hour]++;
      } else {
        $inf++;
      }
      $sum += $hour;
    }

    END {
      my $N = 0;
      for (my $i = 0; $i <= $#arr; $i++) {
        $N += $arr[$i];
        print "'${var}'_bucket{ipver=\"'${v:-4}'\",orport=\"'$orport'\",mode=\"'$mode'\",le=\"$i\"} $N\n";
      }
      my $count = $N + $inf;
      print "'${var}'_bucket{ipver=\"'${v:-4}'\",orport=\"'$orport'\",mode=\"'$mode'\",le=\"+Inf\"} $count\n";
      print "'${var}'_count{ipver=\"'${v:-4}'\",orport=\"'$orport'\",mode=\"'$mode'\"} $count\n";
      print "'${var}'_sum{ipver=\"'${v:-4}'\",orport=\"'$orport'\",mode=\"'$mode'\"} $sum\n";
    }'
}


function printMetrics() {
  ###############################
  # DROPed packets
  #
  var="torutils_packets"
  echo -e "# HELP $var Total number of packets\n# TYPE $var gauge"
  for v in "" 6
  do
    if [[ -z $v ]]; then
      pars="pkts bytes target prot opt in out source destination misc"
    else
      pars="pkts bytes target prot     in out source destination misc"
    fi

    for table in filter
    do
      ip${v}tables -nvxL -t $table |
      grep 'DROP' | grep -v -e "^Chain" -e "^  *pkts" -e "^$" |
      while read -r $pars
      do
        dpt=$(grep -Eo "(dpt:[0-9]+)" <<< "$misc" | cut -f 2 -d':')
        echo "$var{ipver=\"${v:-4}\",table=\"$table\",target=\"$target\",prot=\"$prot\",dpt=\"$dpt\",misc=\"$misc\"} $pkts"
      done
    done
  done


  ###############################
  # ipset sizes
  #
  var="torutils_ipset_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6
  do
    for mode in "ddos"
    do
      ipset list -t | grep -e "^N" | xargs -n 6 | awk '/tor-'$mode''$v'-/ { print $2, $6 }' |
      while read -r name size
      do
        orport=$(cut -f 3 -d'-' <<< $name)
        echo "$var{ipver=\"${v:-4}\",orport=\"$orport\",mode=\"$mode\"} $size"
      done
    done
  done


  ###############################
  # ipset timeout values
  #
  var="torutils_ipset_timeout"
  echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram"
  for v in "" 6
  do
    for mode in "ddos"
    do
      ipset list -t | grep -e "^Name" | awk '/tor-'$mode''$v'-/ { print $2 }' |
      while read -r name
      do
        orport=$(cut -f 3 -d'-' <<< $name)
        ipset list -s $name | sed -e '1,8d' | cut -f 3 -d ' ' | _histogram
      done
    done
  done


  ###############################
  # hashlimit sizes
  #
  var="torutils_hashlimit_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6
  do
    for mode in "ddos" "rate"
    do
      wc -l /proc/net/ip${v}t_hashlimit/tor-$mode-* |
      grep -v ' total' |
      while read -r count name
      do
        orport=$(cut -f3 -d'-' <<< $name)
        echo "$var{ipver=\"${v:-4}\",orport=\"$orport\",mode=\"$mode\"} $count"
      done
    done
  done
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

datadir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux
cd $datadir

tmpfile=$(mktemp /tmp/metrics_XXXXXX.tmp)
echo "# $0   $(date -R)" > $tmpfile
printMetrics >> $tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/torutils.prom
