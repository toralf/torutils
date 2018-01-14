#!/bin/sh
#
#set -x

# start a python web server daemon in /tmp/websvc
# optional parameters: $1: port (default: random), $2: ip-address (default: 127.0.0.1)
#

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

pgrep -af /tmp/websvc.py
if [[ $? -eq 0 ]]; then
	echo "I'm already running ! Exiting ...."
	echo
	exit 1
fi

dir=/tmp/websvc.d
log=/tmp/websvc.log

truncate -s0 $log
mkdir $dir
cp $(dirname $0)/websvc.py /tmp
chmod go-rwx /tmp/websvc{,.log,.py}
chown -R websvc:websvc /tmp/websvc{,.log,.py}

# start it only within $dir !
#
cd $dir || exit 1

# choose an arbitrary unprivileged port if no one is given
#
let p="$((RANDOM % 64510 )) + 1025"
command="/tmp/websvc.py --port ${1:-$p} --address ${2:-127.0.0.1}"
echo "will run now: '$command'"
su websvc -c "nice $command &> $log &"
sleep 1
rm /tmp/websvc.py

if [[ -s $log ]]; then
  echo "$0: failed to start"
  echo
  cat $log
  echo
else
  pgrep -af /tmp/websvc.py
fi
