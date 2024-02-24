#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# use node_exporter's "textfile" feature to send metrics to Prometheus

# set the Prometheus label "nickname"  to the value of the Tor nickname
function _orport2nickname() {
  local opt=${1:-UNSET}

  echo -n "gnampf"
  case $opt in
  443) echo "1" ;;
  9001) echo "2" ;;
  8443) echo "3" ;;
  9443) echo "4" ;;
  5443) echo "5" ;;
  esac
}

function _histogram() {
  perl -wane '
    BEGIN {
      @arr = (0) x 24;  # 0-23 hour
      $inf = 0;         # anything above
      $sum = 0;
    }
    {
      chomp();
      my $hour = int(($F[2]-1)/3600);
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
        print "'${var}'_bucket{ipver=\"'${v:-4}'\",nickname=\"'$nickname'\",mode=\"'$mode'\",le=\"$i\"} $N\n";
      }
      my $count = $N + $inf;
      print "'${var}'_bucket{ipver=\"'${v:-4}'\",nickname=\"'$nickname'\",mode=\"'$mode'\",le=\"+Inf\"} $count\n";
      print "'${var}'_count{ipver=\"'${v:-4}'\",nickname=\"'$nickname'\",mode=\"'$mode'\"} $count\n";
      print "'${var}'_sum{ipver=\"'${v:-4}'\",nickname=\"'$nickname'\",mode=\"'$mode'\"} $sum\n";
    }'
}

function printMetrics() {
  local count
  local mode
  local name
  local nickname
  local orport
  local var

  ###############################
  # ipset timeout values
  #
  mode="ddos"
  var="torutils_ipset_timeout"
  echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram"
  for v in "" 6; do
    ipset list -n |
      grep '^tor-'${mode}${v}'-' |
      while read -r name; do
        orport=$(cut -f 3 -d '-' -s <<<$name)
        nickname=$(_orport2nickname $orport)
        {
          ipset list -s $name | sed -e '1,8d' | _histogram >$tmpfile.$name.tmp
          chmod a+r $tmpfile.$name.tmp
          mv $tmpfile.$name.tmp $datadir/torutils-$name.prom
        } &
      done
  done

  ###############################
  # dropped packets
  #
  var="torutils_dropped_state_packets"
  echo -e "# HELP $var Total number of dropped packets due to wrong TCP state\n# TYPE $var gauge"
  for v in "" 6; do
    ip${v}tables -nvxL -t filter |
      grep ' DROP ' | grep -e " ctstate INVALID" -e " state NEW" | awk '{ print $1, $NF }' |
      while read -r pkts state; do
        echo "$var{ipver=\"${v:-4}\",state=\"$state\"} $pkts"
      done
  done

  var="torutils_dropped_ddos_packets"
  echo -e "# HELP $var Total number of dropped packets due to being classified as DDoS\n# TYPE $var gauge"
  for v in "" 6; do
    # shellcheck disable=SC2034
    ip${v}tables -nvxL -t filter |
      grep ' DROP ' | grep ' match-set tor-ddos'$v'-' |
      while read -r pkts remain; do
        name=$(grep -Eo ' tor-ddos.* ' <<<$remain | tr -d ' ')
        orport=$(cut -f 3 -d '-' -s <<<$name)
        nickname=$(_orport2nickname $orport)
        echo "$var{ipver=\"${v:-4}\",nickname=\"$nickname\"} $pkts"
      done
  done

  ###############################
  # ipset sizes
  #
  var="torutils_ipset_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    ipset list -t | grep -e "^N" | xargs -L 2 | awk '/^Name: tor-/ { print $2, $6 }' |
      if [[ $v == "6" ]]; then
        grep -e "6 " -e "6-"
      else
        grep -v -e "6 " -e "6-"
      fi |
      while read -r name size; do
        mode=$(cut -f 2 -d '-' -s <<<$name | tr -d '6')
        if [[ $name =~ 'multi' ]]; then
          count=$(cut -f 3 -d '-' -s <<<$name)
          echo "$var{ipver=\"${v:-4}\",mode=\"$mode\",count=\"$count\"} $size"
        elif [[ $name =~ 'trust' ]]; then
          echo "$var{ipver=\"${v:-4}\",mode=\"$mode\"} $size"
        else
          orport=$(cut -f 3 -d '-' -s <<<$name)
          nickname=$(_orport2nickname $orport)
          echo "$var{ipver=\"${v:-4}\",mode=\"$mode\",nickname=\"$nickname\"} $size"
        fi
      done
  done

  ###############################
  # hashlimit sizes
  #
  mode="ddos"
  var="torutils_hashlimit_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    wc -l /proc/net/ip${v}t_hashlimit/tor-$mode-* |
      grep -v ' total' |
      while read -r count name; do
        orport=$(cut -f 3 -d '-' -s <<<$name)
        nickname=$(_orport2nickname $orport)
        echo "$var{ipver=\"${v:-4}\",nickname=\"$nickname\",mode=\"$mode\"} $count"
      done
  done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

tmpfile=$(mktemp /tmp/metrics_torutils_XXXXXX.tmp)

datadir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux
cd $datadir

echo "# $0   $(date -R)" >$tmpfile
printMetrics >>$tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/torutils.prom
