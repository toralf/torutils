#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# local hack (at system mr-fox): set the Prometheus label "nickname" to the value of the torrc
function _orport2nickname() {
  local orport=${1?PORT IS UNSET}

  case $orport in
  443) echo "fuchs1" ;;
  9001) echo "fuchs2" ;;
  8443) echo "fuchs3" ;;
  9443) echo "fuchs4" ;;
  5443) echo "fuchs5" ;;
  *) echo "orport-$orport" ;;
  esac
}

function printMetricsIptables() {
  local tables4=$(iptables -nvx -L INPUT)
  local tables6=$(ip6tables -nvx -L INPUT)

  local var

  var="torutils_dropped_state_packets"
  echo -e "# HELP $var Total number of dropped packets due to wrong TCP state\n# TYPE $var gauge"

  grep 'DROP .*state [NEW|INVALID]' <<<$tables4 |
    awk '{ print $1, $NF }' |
    while read -r pkts state; do
      echo "$var{ipver=\"v4\",state=\"$state\"} $pkts"
    done

  grep 'DROP .*state [NEW|INVALID]' <<<$tables6 |
    awk '{ print $1, $NF }' |
    while read -r pkts state; do
      echo "$var{ipver=\"v6\",state=\"$state\"} $pkts"
    done

  var="torutils_dropped_ipset_packets"
  echo -e "# HELP $var Total number of dropped packets by ipset\n# TYPE $var gauge"

  cat <<<"$tables4
$tables6" |
    grep " DROP .* match-set torutils-ddos-" |
    awk '{ print $1, $13 }' |
    while read -r pkts name; do
      read -r ipver orport netmask < <(cut -f 3-5 -d '-' <<<$name | tr '-' ' ')
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "$var{nickname=\"$nickname\",ipver=\"$ipver\",netmask=\"$netmask\"} $pkts"
    done
}

function _histogram() {
  # shellcheck disable=SC2154
  LC_ALL=$LANG perl -wane '
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
        print "'$var'_bucket{nickname=\"'$nickname'\",ipver=\"'$ipver'\",netmask=\"'$netmask'\",le=\"$i\"} $N\n";
      }
      my $count = $N + $inf;
      print "'$var'_bucket{nickname=\"'$nickname'\",ipver=\"'$ipver'\",netmask=\"'$netmask'\",le=\"+Inf\"} $count\n";
      print "'$var'_count{nickname=\"'$nickname'\",ipver=\"'$ipver'\",netmask=\"'$netmask'\"} $count\n";
    }'
}

function printMetricsIpsets() {
  local var

  # ipset timeout values (for histogram)

  export var="torutils_ipset_timeout"
  echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram"

  ipset list -n |
    grep '^torutils-ddos-' |
    while read -r name; do
      read -r ipver orport netmask < <(cut -f 3-5 -d '-' <<<$name | tr '-' ' ')
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "\"nickname=$nickname; ipver=$ipver; netmask=$netmask; ipset list $name | sed -e '1,8d' | _histogram\""
    done |
    xargs -r -P $cpus -L 1 bash -c

  # ipset sizes

  var="torutils_ipset"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"

  ipset list -t |
    grep "^N" |
    xargs -r -L 2 |
    awk '/^Name: torutils-ddos-/ { print $2, $6 }' |
    while read -r name size; do
      read -r ipver orport netmask < <(cut -f 3-5 -d '-' <<<$name | tr '-' ' ')
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "$var{nickname=\"$nickname\",ipver=\"$ipver\",netmask=\"$netmask\"} $size"
    done
}

function printMetricsHashes() {
  local var

  var="torutils_hashlimit"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"

  wc -l /proc/net/ip{,6}t_hashlimit/torutils-ddos-* 2>/dev/null |
    grep -v 'total' |
    while read -r count name; do
      read -r ipver orport netmask suffix < <(cut -f 3-6 -d '-' <<<$name | tr '-' ' ')
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "$var{nickname=\"$nickname\",ipver=\"$ipver\",netmask=\"$netmask\",suffix=\"${suffix-}\"} $count"
    done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

intervall=${1:-0} # 0 == finish after running once
datadir=${2:-/var/lib/node_exporter}
if [[ $# -gt 2 ]]; then
  exit 1
fi

lockfile="/tmp/torutils-$(basename $0).lock"
if [[ -s $lockfile ]]; then
  pid=$(<$lockfile)
  if kill -0 $pid &>/dev/null; then
    exit 0
  else
    echo "ignore lock file, pid=$pid" >&2
  fi
fi
echo $$ >"$lockfile"

trap 'rm -f $lockfile' INT QUIT TERM EXIT

# if nickname is neither given nor found then use _orport2nickname()
export NICKNAME=${TORUTILS_NICKNAME:-$(grep "^Nickname " /etc/tor/torrc 2>/dev/null | awk '{ print $2 }')}

cd $datadir

export -f _histogram _orport2nickname

cpus=$(((1 + $(nproc)) / 2))
while :; do
  now=$EPOCHSECONDS

  # clean old data if tor is not running
  if ! pgrep -f /usr/bin/tor 1>/dev/null; then
    truncate -s 0 $datadir/torutils.prom
  else
    tmpfile=$(mktemp /tmp/torutils_metrics_XXXXXX.tmp)
    echo "# $0   $(date -R)" >$tmpfile
    printMetricsIptables >>$tmpfile
    if type ipset 1>/dev/null 2>&1; then
      printMetricsIpsets >>$tmpfile
      printMetricsHashes >>$tmpfile
    fi
    chmod a+r $tmpfile
    mv $tmpfile $datadir/torutils.prom
  fi

  if [[ $intervall -eq 0 ]]; then
    break
  fi
  diff=$((EPOCHSECONDS - now))
  if [[ $diff -lt $intervall ]]; then
    sleep $((intervall - diff))
  fi
done
