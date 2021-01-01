#!/bin/sh
# set -x

# setup an onion service

# $1: <ip address>, $2: <port number>,  $3: [unset or "non"]

set -euf

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 2
fi

dir=/tmp/onionsvc.d
mkdir -m 0700     $dir
chown -R tor:tor  $dir

cat << EOF > $dir/torrc
User tor

SandBox 1

RunAsDaemon 1

DataDirectory $dir/data
PIDFile       $dir/tor.pid

SocksPort 0

ControlPort 9099      # https://github.com/mikeperry-tor/vanguards
CookieAuthentication 1

Log debug file $dir/debug.log
Log info file $dir/info.log
Log notice file $dir/notice.log
AvoidDiskWrites 1

BandwidthRate   512 KBytes
BandwidthBurst 1024 KBytes

HiddenServiceDir $dir/data/osdir
HiddenServicePort 80 ${1:-127.0.0.1}:${2:-1234}

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

echo
echo "onion address:  $(tail -v $dir/data/osdir/hostname)"
echo
