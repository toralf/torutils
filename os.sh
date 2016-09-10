#!/bin/sh
#
#set -x

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 2
fi

os=/tmp/os

if [[ -e $os ]]; then
  echo -en "\n $os does already exist "
  if [[ "$1" = "-f" ]]; then
    echo " -  forced to overwrite it"
  else
    echo "stopping !"
    echo
    exit 1
  fi
fi

if [[ -s $os/tor.pid ]]; then
  pid=$(cat $os/tor.pid)
  kill -s 0 $pid
  if [[ $? -eq 0 ]]; then
    echo "there's already a running instance at pid $pid , exiting ..."
    echo
    exit 3
  else
    echo "removing obsolete old pid-file containing pid $pid"
    rm $os/tor.pid
  fi
fi

mkdir -m 0700 $os 2>/dev/null
chown tor:tor $os

cat << EOF > $os/torrc
User tor

RunAsDaemon 1

DataDirectory $os/data
PIDFile       $os/tor.pid

SocksPort   0

SandBox 1

#Log debug   file $os/debug.log
#Log info    file $os/info.log
Log notice  file $os/notice.log

BandwidthRate  500 KBytes
BandwidthBurst 600 Kbytes

HiddenServiceDir $os/data/osdir
HiddenServicePort 80 127.0.0.1:1234
#HiddenServicePort 80 [::1]:1234

EOF

chown tor:tor /tmp/os/torrc

/usr/bin/tor -f $os/torrc
rc=$?

echo "pid       $(cat $os/tor.pid)"
sleep 1
echo "hostname  $(cat $os/data/osdir/hostname)"

exit $rc
