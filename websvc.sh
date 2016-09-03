#!/bin/sh
#
#set -x

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

dir=/tmp/websvc
log=/tmp/websvc.log

mkdir $dir 2>/dev/null
echo "$(dd if=/dev/urandom 2>/dev/null | base64 | sed -e 's/[^abcdefghijklmnopqrstuvwxyz234567]//g' | cut -c1-16 | head -n1).onion" > $dir/address.txt
cp $(dirname $0)/websvc.py /tmp

chown -R websvc:websvc /tmp/websvc*
chmod 700 /tmp/websvc.py
chmod 640 $log
chmod 750 $dir

cd $dir
su websvc -c "cd /tmp/websvc && /tmp/websvc.py &>> $log" &
sleep 2
rm /tmp/websvc.py
