#!/bin/sh
#
#set -x

# start a python web server daemon in $dir
# optional parameters: $1: port (default: random), $2: ip-address (default: 127.0.0.1)
#

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

echo "checking if I'm already running ..."
pgrep -af /tmp/websvc.py

if [[ $? -eq 0 ]]; then
	echo " Yes ! Exiting ..."
	echo
	exit 1
fi

dir=/tmp/websvc.d
log=/tmp/websvc.log

if [[ ! -d $dir ]]; then
  mkdir $dir || exit 1
fi
chown websvc:websvc $dir
chmod g+s $dir

truncate -s0 $log
chmod 600 /tmp/websvc.log
chown websvc:websvc /tmp/websvc.log

# choose an arbitrary unprivileged port if no one is given
#
let port="$((RANDOM % 64510 )) + 1025"

cp $(dirname $0)/websvc.py /tmp
chown websvc:websvc /tmp/websvc.py
chmod 700 /tmp/websvc.py

command="cd $dir && /tmp/websvc.py --port ${1:-$port} --address ${2:-127.0.0.1}"
echo "will run now: '$command'"
su websvc -c "nice bash -c '$command &>>$log' &>>$log &"
sleep 1

if [[ -s $log ]]; then
  echo "$0: failed to start"
  echo
  cat $log
  echo
else
  pgrep -af /tmp/websvc.py
fi
