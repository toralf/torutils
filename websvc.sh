#!/bin/sh
#
# set -x

# start a python web server
# $1: <ip address>, $2: <port number>, $3 (optional): "--is_ipv6"

set -ef

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

id websvc

pgrep -af /tmp/websvc.py
if [[ $? -eq 0 ]]; then
	echo " I'm already running ... ! Exiting ..."
	echo
	exit 1
fi

dir=/tmp/websvc.d

if [[ -e $dir/data ]]; then
  echo "$dir does already exists! Exiting ..."
  exit 1
fi

mkdir -p $dir/data
chmod -R 700 $dir
chmod -R g+s $dir

cp $(dirname $0)/websvc.py $dir

echo "<h1>This is an empty page.<h1>" > $dir/data/index.html
chmod 444 $dir/data/index.html

log=$dir/websvc.log
truncate -s0 $log

chown -R websvc:websvc  $dir
sudo -u websvc bash -c "cd $dir/data && ../websvc.py --port --address ${1:-127.0.0.1} ${2:-1234} $3 &>>$log"
