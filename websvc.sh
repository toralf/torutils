#!/bin/sh
#
#set -x

# start a python web server daemon in /tmp/websvc
# $1 is the ip-address (default localhost)
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

dir=/tmp/websvc
log=/tmp/websvc.log

truncate -s0 $log
mkdir $dir 2>/dev/null
cp $(dirname $0)/websvc.py /tmp
chmod go-rwx /tmp/websvc{,.log,.py}
chown -R websvc:websvc /tmp/websvc{,.log,.py}

# start it only within $dir !
#
cd $dir || exit 1

# choose a random unprivileged port
#
let p="$((RANDOM % 64000 )) + 1025"
echo "port = $p"
su websvc -c "nice /tmp/websvc.py --address ${1:-127.0.0.1} --port $p &>> $log &"
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
