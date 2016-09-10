#!/bin/sh
#
#set -x

# start a micro web server in /tmp/websvc
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

cp /dev/null $log
mkdir $dir 2>/dev/null
cp $(dirname $0)/websvc.py /tmp
chmod go-rwx /tmp/websvc{,.log,.py}
chown -R websvc:websvc /tmp/websvc{,.log,.py}

# start it only within $dir !
#
cd $dir || exit 1
#su websvc -c "/tmp/websvc.py --address ::1 --port 1234 &>> $log" &
su websvc -c "/tmp/websvc.py --address 127.0.0.1 --port 1234 &>> $log" &

sleep 2
rm /tmp/websvc.py

if [[ -s $log ]]; then
  echo "$0: failed to start"
  echo
  cat $log
  echo
fi
