#!/bin/sh
#
#set -x

# start a minimalistic web server for webroot /tmp/websvc
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
chown -R websvc:websvc /tmp/websvc{,.log,.py}
chmod go-rwx /tmp/websvc{,.log,.py}

# start it within $dir !
#
cd $dir || exit 1
su websvc -c /tmp/websvc.py &>> $log &

sleep 2
rm /tmp/websvc.py

if [[ -s $log ]]; then
  echo "$0: failed to start"
  echo
  cat $log
  echo
fi
