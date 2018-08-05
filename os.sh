#!/bin/sh
#
#set -x

# setup an onion service
# optional parameters: $1: port (default: 1234), $2: address (default: 127.0.0.1), $3: ControlPort

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 2
fi

dir=/tmp/onionsvc.d

if [[ -e $dir ]]; then
  echo -en "\n $dir does already exist"
  echo " exiting ..."
  echo
  exit 1
fi

mkdir -m 0700 $dir
chown -R tor:tor $dir

cat << EOF > $dir/torrc
User tor

RunAsDaemon 1

DataDirectory $dir/data
PIDFile       $dir/tor.pid

ControlPort ${3:-59051}
CookieAuthentication 1

SocksPort 0

Log notice file $dir/notice.log

BandwidthRate  1000 KBytes
BandwidthBurst 1600 Kbytes

HiddenServiceDir $dir/data/osdir
HiddenServiceVersion 3
HiddenServicePort 80 ${2:-127.0.0.1}:${1:-1234}

EOF

chmod 600     $dir/torrc
chown tor:tor $dir/torrc

/usr/bin/tor -f $dir/torrc
rc=$?

echo
echo "onion address:  $(cat $dir/data/osdir/hostname)"
echo

exit $rc
