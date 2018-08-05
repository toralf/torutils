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
log=$dir/websvc.log

if [[ -e $dir/data ]]; then
  echo "$dir does already exists! Exiting ..."
  exit 1
fi

mkdir -p $dir/data || exit 1
chmod -R 775            $dir
chmod -R g+s            $dir
chown -R websvc:websvc  $dir

truncate -s0 $log
chmod 600           $log
chown websvc:websvc $log

cp $(dirname $0)/websvc.py $dir
chmod 700           $dir/websvc.py
chown websvc:websvc $dir/websvc.py

command="cd $dir/data && ../websvc.py --port ${1:-1234} --address ${2:-127.0.0.1}"
echo "will run now: '$command'"
su websvc -c "nice bash -c '$command &>>$log' &>>$log &"
sleep 1

if [[ -s $log ]]; then
  echo "$0: failed to start"
  echo
  cat $log
  echo
else
  pgrep -af websvc.py
fi
