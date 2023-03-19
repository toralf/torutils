#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# use node_exporter's "textfile" feature to pump metrics into Prometheus
# https://prometheus.io/docs/instrumenting/exposition_formats/


function histogram()  {
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
        print "'${var}'_bucket{ipver=\"'${v:-4}'\",orport=\"'$orport'\",le=\"$i\"} $N\n";
      }
      my $count = $N + $inf;
      print "'${var}'_bucket{ipver=\"'${v:-4}'\",orport=\"'$orport'\",le=\"+Inf\"} $count\n";
      print "'${var}'_count{ipver=\"'${v:-4}'\",orport=\"'$orport'\"} $count\n";
      print "'${var}'_sum{ipver=\"'${v:-4}'\",orport=\"'$orport'\"} $sum\n";
    }'
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

datadir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux
if [[ ! -d $datadir ]]; then
  echo -e " exporter directory '$datadir' does not exist" >&2
  exit 1
fi

tmpfile=$datadir/torutils.prom.tmp
echo "# $0   $(date -R)" > $tmpfile
chmod a+r $tmpfile

# iptables table stats
var="torutils_packets"
echo -e "# HELP $var Total number of packets\n# TYPE $var gauge" >> $tmpfile
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
    grep 'DROP' |
    grep -v -e "^Chain" -e "^  *pkts" -e "^$" |
    while read -r $pars
    do
      dpt=$(grep -Eo "(dpt:[0-9]+)" <<< "$misc" | cut -f2 -d':')
      echo "$var{ipver=\"${v:-4}\",table=\"$table\",target=\"$target\",prot=\"$prot\",dpt=\"$dpt\",misc=\"$misc\"} $pkts"
    done >> $tmpfile
  done
done

var="torutils_ipset_total"
echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge" >> $tmpfile
for v in "" 6
do
  ipset list -t | grep -e "^N" | xargs -n 6 | awk '/tor-ddos'$v'-/ { print $2, $6 }' |
  while read -r name size
  do
    orport=$(cut -f3 -d'-' <<< $name)
    echo "$var{ipver=\"${v:-4}\",orport=\"$orport\"} $size" >> $tmpfile
  done
done

var="torutils_ipset_timeout"
echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram" >> $tmpfile
for v in "" 6
do
  ipset list -t | grep -e "^Name" | awk '/tor-ddos'$v'-/ { print $2 }' |
  while read -r name
  do
    orport=$(cut -f 3 -d'-' <<< $name)
    ipset list -s $name | sed -e '1,8d' | cut -f 3 -d ' ' | histogram >> $tmpfile
  done
done

var="torutils_hashlimit_total"
echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge" >> $tmpfile
for v in "" 6
do
  wc -l /proc/net/ip${v}t_hashlimit/*ddos* |
  grep -v ' total' |
  while read -r count name
  do
    orport=$(cut -f3 -d'-' <<< $name)
    echo "$var{ipver=\"${v:-4}\",orport=\"$orport\"} $count" >> $tmpfile
  done
done

var="torutils_hashlimit_timeout"
echo -e "# HELP $var A histogram of hashlimit timeout values\n# TYPE $var histogram" >> $tmpfile
for v in "" 6
do
  for name in /proc/net/ip${v}t_hashlimit/*ddos*
  do
    orport=$(cut -f 3 -d'-' <<< $name)
    cut -f 1 -d ' ' $name | histogram >> $tmpfile
  done
done

mv $tmpfile $datadir/torutils.prom