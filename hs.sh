#!/bin/sh
#

#set -x

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi



hs=/tmp/hs

mkdir -m 0700 $hs
chown tor:tor $hs

cat << EOF > $hs/torrc
User tor

RunAsDaemon 1

DataDirectory $hs/data
PIDFile       $hs/tor.pid

SocksPort   0

Log notice file $hs/notice.log

HiddenServiceDir $hs/data/hsdir
HiddenServicePort 80 127.0.0.1:8080

EOF

/usr/bin/tor -f $hs/torrc
rc=$?

cat $hs/tor.pid
cat $hs/data/hsdir/hostname

exit $rc
