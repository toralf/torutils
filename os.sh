#!/bin/sh
#
#set -x

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

hs=/tmp/hs

if [[ -e $hs ]]; then
  echo -en "\n $hs does already exist "
  if [[ "$1" = "-f" ]]; then
    echo " -  forced to overwrite it"
  else
    echo
    echo
    exit 1
  fi
fi

mkdir -m 0700 $hs 2>/dev/null
chown tor:tor $hs

cat << EOF > $hs/torrc
User tor

RunAsDaemon 1

DataDirectory $hs/data
PIDFile       $hs/tor.pid

SocksPort   0

SandBox 1

Log notice file $hs/notice.log

BandwidthRate  500 KBytes
BandwidthBurst 600 Kbytes

HiddenServiceDir $hs/data/hsdir
HiddenServicePort 80 127.0.0.1:8080
HiddenServicePort 80 [::]:8080

EOF

#  shot up a previously running instance
#
if [[ -s $hs/tor.pid ]]; then
  kill -s 0 $(cat $hs/tor.pid) && kill -s INT $(cat $hs/tor.pid)
fi

/usr/bin/tor -f $hs/torrc
rc=$?

echo "pid       $(cat $hs/tor.pid)"
sleep 2
echo "hostname  $(cat $hs/data/hsdir/hostname)"

exit $rc

