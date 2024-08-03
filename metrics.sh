#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# use node_exporter's "textfile" feature to send metrics to Prometheus

# local quirk
function _orport2nickname() {
  local orport=${1?PORT IS UNSET}

  case $orport in
  443) echo "fuchs1" ;;
  9001) echo "fuchs2" ;;
  8443) echo "fuchs3" ;;
  9443) echo "fuchs4" ;;
  5443) echo "fuchs5" ;;
  esac
}

# local hack at my mr-fox to set the Prometheus label "nickname" to the value of the torrc
function printMetricsIptables() {
  local var
  local tables4
  local tables6

  tables4=$(iptables -nvx -L INPUT -t filter) || return 1
  tables6=$(ip6tables -nvx -L INPUT -t filter) || return 1

  var="torutils_dropped_state_packets"
  echo -e "# HELP $var Total number of dropped packets due to wrong TCP state\n# TYPE $var gauge"
  for v in "" 6; do
    if [[ -z $v ]]; then
      echo "$tables4"
    else
      echo "$tables6"
    fi |
      grep 'DROP .*state [NEW|INVALID]' | awk '{ print $1, $NF }' |
      while read -r pkts state; do
        echo "$var{ipver=\"${v:-4}\",state=\"$state\"} $pkts"
      done
  done

  var="torutils_dropped_ddos_packets"
  echo -e "# HELP $var Total number of dropped packets due to being classified as DDoS\n# TYPE $var gauge"
  for v in "" 6; do
    if [[ -z $v ]]; then
      echo "$tables4"
    else
      echo "$tables6"
    fi |
      grep ' DROP .* match-set tor-ddos'$v'-' | awk '{ print $1, $11 }' |
      while read -r pkts dport; do
        orport=$(cut -f 2 -d ':' <<<$dport)
        nickname=${NICKNAME:-$(_orport2nickname $orport)}
        echo "$var{ipver=\"${v:-4}\",nickname=\"$nickname\"} $pkts"
      done
  done
}

function _ipset2nickname() {
  local name=${1?NAME IS UNSET}

  local orport=$(cut -f 3 -d '-' -s <<<$name)
  _orport2nickname $orport
}

function _histogram() {
  perl -wane '
    BEGIN {
      @arr = (0) x 24;  # 0-23 hour
      $inf = 0;         # anything above
    }

    {
      my $hour = int( ($F[2] - 1) / 3600);
      if ($hour <= 23) {
        $arr[$hour]++
      } else {
        $inf++;
      }
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
    }'
}

function printMetricsIpsets() {
  local count
  local mode
  local name
  local var

  ###############################
  # ipset timeout values
  #
  export mode="ddos"
  export var="torutils_ipset_timeout"
  echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram"
  for v in "" 6; do
    ipset list -n |
      grep '^tor-'${mode}${v}'-' |
      while read -r name; do
        export nickname=${NICKNAME:-$(_ipset2nickname $name)}
        echo "nickname=$nickname; v=$v; ipset list -s $name | sed -e '1,8d' | _histogram >$tmpfile.$name.tmp; chmod a+r $tmpfile.$name.tmp; mv $tmpfile.$name.tmp $datadir/torutils-$name.prom"
      done |
      xargs -r -P $cpus -I '{}' bash -c "{}"
  done

  ###############################
  # ipset sizes
  #
  var="torutils_ipset_total"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    ipset list -t | grep "^N" | xargs -L 2 | awk '/^Name: tor-/ { print $2, $6 }' |
      if [[ -z $v ]]; then
        grep -v -E -e "-[a-z]+6[ -]"
      else
        grep -E -e "-[a-z]+6[ -]"
      fi |
      while read -r name size; do
        mode=$(cut -f 2 -d '-' -s <<<$name | tr -d '6')
        if [[ $name =~ 'trust' ]]; then
          echo "$var{ipver=\"${v:-4}\",mode=\"$mode\"} $size"
        else
          nickname=${NICKNAME:-$(_ipset2nickname $name)}
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
        nickname=${NICKNAME:-$(_ipset2nickname $name)}
        echo "$var{ipver=\"${v:-4}\",nickname=\"$nickname\",mode=\"$mode\"} $count"
      done
  done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

export datadir=${1:-/var/lib/node_exporter}
cd $datadir

export NICKNAME=${2:-$(grep "^Nickname " /etc/tor/torrc 2>/dev/null | awk '{ print $2 }')} # if neither given nor found then use _orport2nickname()
export cpus=$(((1 + $(nproc)) / 2))
export -f _histogram _ipset2nickname _orport2nickname

export tmpfile=$(mktemp /tmp/metrics_torutils_XXXXXX.tmp)
echo "# $0   $(date -R)" >$tmpfile
printMetricsIptables >>$tmpfile
if type ipset 1>/dev/null 2>&1; then
  printMetricsIpsets >>$tmpfile
fi
chmod a+r $tmpfile
mv $tmpfile $datadir/torutils.prom
