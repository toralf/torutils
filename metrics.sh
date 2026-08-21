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

  local var pkts

  var="torutils_dropped_packets_ctstate"
  echo -e "# HELP $var Total number of dropped packets by ctstate\n# TYPE $var gauge"

  grep -E 'DROP .* ctstate (NEW|INVALID)' <<<$tables4 |
    awk '{ print $1, $NF }' |
    while read -r pkts ctstate; do
      echo "$var{ipver=\"v4\",ctstate=\"$ctstate\"} $pkts"
    done

  grep -E 'DROP .* ctstate (NEW|INVALID)' <<<$tables6 |
    awk '{ print $1, $NF }' |
    while read -r pkts ctstate; do
      echo "$var{ipver=\"v6\",ctstate=\"$ctstate\"} $pkts"
    done

  var="torutils_dropped_packets_ddos"
  echo -e "# HELP $var Total number of dropped packets by DDoS\n# TYPE $var gauge"

  cat <<<"$tables4
$tables6" |
    grep " DROP .* match-set torutils-ddos-v" |
    awk '{ print $1, $13 }' |
    while read -r pkts name; do
      read -r ipver orport netmask < <(cut -f 3-5 -d '-' <<<$name | tr '-' ' ')
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "$var{nickname=\"$nickname\",ipver=\"$ipver\",netmask=\"$netmask\"} $pkts"
    done

  var="torutils_dropped_packets_tarpit"
  echo -e "# HELP $var Total number of dropped packets by tarpit\n# TYPE $var gauge"

  pkts=$(grep " DROP .* match-set torutils-tarpit-v4" <<<$tables4 | awk '{ print $1 }')
  echo "$var{ipver=\"v4\"} $pkts"

  pkts=$(grep " DROP .* match-set torutils-tarpit-v6" <<<$tables6 | awk '{ print $1 }')
  echo "$var{ipver=\"v6\"} $pkts"
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

  local names=$(
    {
      iptables -nvL INPUT
      ip6tables -nvL INPUT
    } |
      grep 'match-set torutils-ddos-v' |
      awk '{ print $13 }'
  )

  xargs -r -n 1 <<<$names |
    while read -r name; do
      read -r ipver orport netmask < <(cut -f 3-5 -d '-' <<<$name | tr '-' ' ')
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "\"nickname=$nickname; ipver=$ipver; netmask=$netmask; ipset list $name | sed -e '1,8d' | _histogram\""
    done |
    xargs -r -P $cpus -L 1 bash -c

  # ipset sizes

  var="torutils_ipset"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"

  xargs -r -n 1 <<<$names |
    while read -r name; do
      size=$(ipset list -t $name | grep "^Number" | cut -f 2 -d ':')
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
