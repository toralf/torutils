#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# use node_exporter's "textfile" feature to send metrics to Prometheus

function _histogram() {
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
  # dropped packets stats
  #
  local var="torutils_state_packets"
  echo -e "# HELP $var Total number of dropped state packets\n# TYPE $var gauge"
  for v in "" 6; do
    ip${v}tables -nvxL -t filter |
      grep -F ' DROP ' | grep -v -e "^Chain " | grep -F -e " ctstate INVALID" -e " state NEW" | awk '{ print $1, $NF }' |
      while read -r pkts state; do
        echo "$var{ipver=\"${v:-4}\",state=\"$state\"} $pkts"
      done
  done

  local var="torutils_syn_packets"
  echo -e "# HELP $var Total number of dropped syn packets\n# TYPE $var gauge"
  for v in "" 6; do
    # shellcheck disable=SC2034
    ip${v}tables -nvxL -t filter |
      grep -F ' DROP ' | grep -v -e "^Chain" | grep -F ' match-set tor-ddos-' | awk '{ print $1, $14 }' |
      while read -r pkts name; do
        orport=$(cut -f 3 -d '-' -s <<<$name)
        echo "$var{ipver=\"${v:-4}\",orport=\"$orport\"} $pkts"
      done
  done

  ###############################
  # ipset ddos sizes
  #
  var="torutils_ipset_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    ipset list -t | grep -e "^N" | xargs -n 6 | awk '/tor-ddos'$v'-/ { print $2, $6 }' |
      while read -r name size; do
        orport=$(cut -f 3 -d '-' -s <<<$name)
        echo "$var{ipver=\"${v:-4}\",orport=\"$orport\",mode=\"ddos\"} $size"
      done
  done

  ###############################
  # ipset ddos timeout values
  #
  local mode="ddos"
  var="torutils_ipset_timeout"
  echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram"
  for v in "" 6; do
    ipset list -t | grep -e "^Name" | awk '/tor-ddos'$v'-/ { print $2 }' |
      while read -r name; do
        orport=$(cut -f 3 -d '-' -s <<<$name)
        ipset list -s $name | sed -e '1,8d' | cut -f 3 -d ' ' -s | _histogram
      done
  done

  ###############################
  # hashlimit sizes
  #
  var="torutils_hashlimit_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    for mode in "ddos" "rate"; do
      wc -l /proc/net/ip${v}t_hashlimit/tor-$mode-* |
        grep -v ' total' |
        while read -r count name; do
          orport=$(cut -f 3 -d '-' -s <<<$name)
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

tmpfile=$(mktemp /tmp/metrics_torutils_XXXXXX.tmp)
echo "# $0   $(date -R)" >$tmpfile
printMetrics >>$tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/torutils.prom
