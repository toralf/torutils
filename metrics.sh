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
  local tables4=$($ipt -nvx -L INPUT -t filter 2>/dev/null)
  local tables6=$($ip6t -nvx -L INPUT -t filter 2>/dev/null)

  local var

  var="torutils_dropped_state_packets"
  echo -e "# HELP $var Total number of dropped packets due to wrong TCP state\n# TYPE $var gauge"
  for v in "" 6; do
    if [[ -z $v ]]; then
      echo "$tables4"
    else
      echo "$tables6"
    fi |
      grep 'DROP .*state [NEW|INVALID]' |
      awk '{ print $1, $NF }' |
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
      grep ' DROP .* match-set tor-ddos'$v'-' |
      awk '{ print $1, $11 }' |
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
        echo "\"nickname=$nickname; v=$v; ipset list -s $name | sed -e '1,8d' | _histogram\""
      done |
      xargs -r -P $cpus -L 1 bash -c
  done

  ###############################
  # ipset sizes
  #

  var="torutils_ipset"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    ipset list -t |
      grep "^N" |
      xargs -L 2 |
      awk '/^Name: tor-/ { print $2, $6 }' |
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
          echo "$var{ipver=\"${v:-4}\",nickname=\"$nickname\",mode=\"$mode\"} $size"
        fi
      done
  done

  ###############################
  # hashlimit sizes
  #
  mode="ddos"

  var="torutils_hashlimit"
  echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge"
  for v in "" 6; do
    # --total=never is not known in Debians (bookworm) "wc"
    wc -l /proc/net/ip${v}t_hashlimit/tor-$mode-* |
      grep -v 'total' |
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
