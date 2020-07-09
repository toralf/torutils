#!/bin/sh
#
# set -x

# setup an onion service
# $1: <port number>, $2: <ip address>

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 2
fi

dir=/tmp/onionsvc.d

if [[ -e $dir ]]; then
  echo
  echo " $dir does already exist"
  echo " exiting ..."
  echo
  exit 1
fi

mkdir -m 0700     $dir
chown -R tor:tor  $dir

cat << EOF > $dir/torrc
User tor

SandBox 1

RunAsDaemon 1

DataDirectory $dir/data
PIDFile       $dir/tor.pid

SocksPort 0

Log notice file $dir/notice.log
AvoidDiskWrites 1

BandwidthRate   512 KBytes
BandwidthBurst 1024 KBytes

HiddenServiceDir $dir/data/osdir
HiddenServicePort 80 ${2:-127.0.0.1}:${1:-1234}

EOF

if [[ "$3" = "non" ]]; then
  cat << EOF >> $dir/torrc

HiddenServiceNonAnonymousMode 1
HiddenServiceSingleHopMode 1

EOF
fi

chmod 600     $dir/torrc
chown tor:tor $dir/torrc

/usr/bin/tor -f $dir/torrc
rc=$?

echo
echo "onion address:  $(tail -v $dir/data/osdir/hostname)"
echo

exit $rc
