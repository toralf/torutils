#!/bin/sh
#
#set -x

# setup an onion service
# optional parameters: $1: port (default: 1234), $2: address (default: 127.0.0.1), $3: ControlPort

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 2
fi

os=/tmp/os

if [[ -e $os ]]; then
  echo -en "\n $os does already exist"
  if [[ "$1" = "-f" ]]; then
    echo " -  forced to overwrite it"
  else
    echo " exiting ..."
    echo
    exit 1
  fi
fi

if [[ -s $os/tor.pid ]]; then
  pid=$(cat $os/tor.pid)
  kill -s 0 $pid
  if [[ $? -eq 0 ]]; then
    echo "there's a running instance at pid=$pid, exiting ..."
    echo
    exit 3
  else
    echo "removing stalled old pid-file (pid=$pid)"
    rm $os/tor.pid
  fi
fi

mkdir -m 0700 $os
chown -R tor:tor $os

cat << EOF > $os/torrc
User tor

RunAsDaemon 1

DataDirectory $os/data
PIDFile       $os/tor.pid

ControlPort ${3:-59051}
CookieAuthentication 1

SocksPort 0

SandBox 1

Log notice file $os/notice.log

# BandwidthRate  500 KBytes
# BandwidthBurst 600 Kbytes

HiddenServiceDir $os/data/osdir
HiddenServiceVersion 3
HiddenServicePort 80 ${2:-127.0.0.1}:${1:-1234}

EOF
chown tor:tor /tmp/os/torrc

/usr/bin/tor -f $os/torrc
rc=$?

echo "hostname  $(cat $os/data/osdir/hostname)"
sleep 1
pid=$(cat $os/tor.pid 2>/dev/null)
echo "pid       $pid"
ps -efla | grep $pid

exit $rc
