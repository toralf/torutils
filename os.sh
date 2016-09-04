#!/bin/sh
#
#set -x

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

os=/tmp/os

if [[ -e $os ]]; then
  echo -en "\n $os does already exist "
  if [[ "$1" = "-f" ]]; then
    echo " -  forced to overwrite it"
  else
    echo
    echo
    exit 1
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

Log notice file $os/notice.log

BandwidthRate  500 KBytes
BandwidthBurst 600 Kbytes

HiddenServiceDir $os/data/osdir
HiddenServicePort 80 127.0.0.1:8080
HiddenServicePort 80 [::]:8080

EOF

#  shot up a previously running instance
#
if [[ -s $os/tor.pid ]]; then
  kill -s 0 $(cat $os/tor.pid) && kill -s INT $(cat $os/tor.pid)
fi

/usr/bin/tor -f $os/torrc
rc=$?

echo "pid       $(cat $os/tor.pid)"
sleep 2
echo "hostname  $(cat $os/data/osdir/hostname)"

exit $rc

