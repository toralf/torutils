#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# local hack (at system mr-fox) to set the Prometheus label "nickname" to the value of the torrc
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

function printMetricsIptables() {
  local tables4=$($ipt -nvx -L INPUT -t filter)
  local tables6=$($ip6t -nvx -L INPUT -t filter)

  local var

  var="torutils_dropped_state_packets"
  echo -e "# HELP $var Total number of dropped packets due to wrong TCP state\n# TYPE $var gauge"

  grep 'DROP .*state [NEW|INVALID]' <<<$tables4 |
    awk '{ print $1, $NF }' |
    while read -r pkts state; do
      echo "$var{ipver=\"4\",state=\"$state\"} $pkts"
    done

  grep 'DROP .*state [NEW|INVALID]' <<<$tables6 |
    awk '{ print $1, $NF }' |
    while read -r pkts state; do
      echo "$var{ipver=\"6\",state=\"$state\"} $pkts"
    done

  var="torutils_dropped_ipset_packets"
  echo -e "# HELP $var Total number of dropped packets by ipset\n# TYPE $var gauge"

  grep " DROP .* match-set tor-ddos-" <<<$tables4 |
    awk '{ print $1, $11 }' |
    while read -r pkts dport; do
      orport=$(cut -f 2 -d ':' <<<$dport)
      nickname=${NICKNAME:-$(_orport2nickname $orport)}
      echo "$var{ipver=\"4\",nickname=\"$nickname\",netmask=\"32\"} $pkts"
    done

  for netmask in 64 80 128; do
    grep " DROP .* match-set tor-ddos$netmask-" <<<$tables6 |
      awk '{ print $1, $11 }' |
      while read -r pkts dport; do
        orport=$(cut -f 2 -d ':' <<<$dport)
        nickname=${NICKNAME:-$(_orport2nickname $orport)}
        echo "$var{ipver=\"6\",nickname=\"$nickname\",netmask=\"$netmask\"} $pkts"
      done
  done
}

function _ipset2nickname() {
  local name=${1?NAME IS UNSET}

  local orport=$(cut -f 3 -d '-' -s <<<$name)
  _orport2nickname $orport
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
        print "'$var'_bucket{ipver=\"'$v'\",nickname=\"'$nickname'\",netmask=\"'$netmask'\",le=\"$i\"} $N\n";
      }
      my $count = $N + $inf;
      print "'$var'_bucket{ipver=\"'$v'\",nickname=\"'$nickname'\",netmask=\"'$netmask'\",le=\"+Inf\"} $count\n";
      print "'$var'_count{ipver=\"'$v'\",nickname=\"'$nickname'\",netmask=\"'$netmask'\"} $count\n";
    }'
}

function printMetricsIpsets() {
  local var

  ###############################
  # ipset timeout values (for histogram)
  #

  export var="torutils_ipset_timeout"
  echo -e "# HELP $var A histogram of ipset timeout values\n# TYPE $var histogram"

  lists=$(ipset list -n)

  grep '^tor-ddos-' <<<$lists |
    while read -r name; do
      nickname=${NICKNAME:-$(_ipset2nickname $name)}
      echo "\"nickname=$nickname; v=4; netmask=32; ipset list $name | sed -e '1,8d' | _histogram\""
    done |
    xargs -r -P $cpus -L 1 bash -c

  for netmask in 64 80 128; do
    grep "^tor-ddos$netmask-" <<<$lists |
      while read -r name; do
        nickname=${NICKNAME:-$(_ipset2nickname $name)}
        echo "\"nickname=$nickname; v=6; netmask=$netmask; ipset list $name | sed -e '1,8d' | _histogram\""
      done |
      xargs -r -P $cpus -L 1 bash -c
  done

  ###############################
  # ipset sizes
  #

  var="torutils_ipset"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"

  lists=$(
    ipset list -t |
      grep "^N" |
      xargs -r -L 2
  )

  awk '/^Name: tor-ddos-/ { print $2, $6 }' <<<$lists |
    while read -r name size; do
      nickname=${NICKNAME:-$(_ipset2nickname $name)}
      echo "$var{ipver=\"4\",nickname=\"$nickname\",netmask=\"32\"} $size"
    done

  for netmask in 64 80 128; do
    awk '/^Name: tor-ddos'$netmask'-/ { print $2, $6 }' <<<$lists |
      while read -r name size; do
        nickname=${NICKNAME:-$(_ipset2nickname $name)}
        echo "$var{ipver=\"6\",nickname=\"$nickname\",netmask=\"$netmask\"} $size"
      done
  done
}

function printMetricsHashes() {
  local var

  ###############################
  # hashlimit sizes
  #
  var="torutils_hashlimit"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"

  wc -l /proc/net/ipt_hashlimit/tor-ddos-* 2>/dev/null |
    grep -v 'total' |
    while read -r count name; do
      nickname=${NICKNAME:-$(_ipset2nickname $name)}
      echo "$var{ipver=\"4\",nickname=\"$nickname\",netmask=\"32\"} $count"
    done

  for netmask in 64 80 128; do
    wc -l /proc/net/ip6t_hashlimit/tor-ddos$netmask-* 2>/dev/null |
      grep -v 'total' |
      while read -r count name; do
        nickname=${NICKNAME:-$(_ipset2nickname $name)}
        echo "$var{ipver=\"6\",nickname=\"$nickname\",netmask=\"$netmask\"} $count"
      done
  done
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

intervall=${1:-0} # 0 == finish after running once
datadir=${2:-/var/lib/node_exporter}

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

# if nickname is not given nor found then use _orport2nickname() called in _ipset2nickname()
export NICKNAME=${3:-$(grep "^Nickname " /etc/tor/torrc 2>/dev/null | awk '{ print $2 }')}

cd $datadir

# check if iptables works or if the legacy variant is needed
ipt="iptables"
ip6t="ip6tables"
set +e
$ipt -nv -L INPUT 1>/dev/null
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  if [[ $rc -eq 4 ]]; then
    ipt+="-legacy"
    ip6t+="-legacy"
    if ! $ipt -nv -L INPUT 1>/dev/null; then
      echo " $ipt is not working" >&2
      exit 1
    fi
  else
    echo " $ipt is not working, rc=$rc" >&2
    exit 1
  fi
fi

export -f _histogram _ipset2nickname _orport2nickname

cpus=$(((1 + $(nproc)) / 2))
while :; do
  now=$EPOCHSECONDS

  # clean old data if tor is not running
  if ! pgrep -f /usr/bin/tor 1>/dev/null; then
    truncate -s 0 $datadir/torutils.prom
  else
    tmpfile=$(mktemp /tmp/metrics_torutils_XXXXXX.tmp)
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
