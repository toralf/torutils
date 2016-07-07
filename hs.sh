#!/bin/sh
#
#set -x

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

hs=/tmp/hs

[[ -e $hs ]] && exit 1
mkdir -m 0700 $hs 
chown tor:tor $hs

cat << EOF > $hs/torrc
User tor

RunAsDaemon 1

DataDirectory $hs/data
PIDFile       $hs/tor.pid

SocksPort   0

Log notice file $hs/notice.log

BandwidthRate  500 KBytes
BandwidthBurst 600 Kbytes

HiddenServiceDir $hs/data/hsdir
HiddenServicePort 80 127.0.0.1:8080
#HiddenServicePort 80 [::]:8080

EOF

/usr/bin/tor -f $hs/torrc
rc=$?

echo "pid       $(cat $hs/tor.pid)"
sleep 2
echo "hostname  $(cat $hs/data/hsdir/hostname)"

exit $rc

