#!/bin/sh
#
#set -x

# start a minimalistic web server for webroot /tmp/websvc
#

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

dir=/tmp/websvc
log=/tmp/websvc.log

cp /dev/null $log
mkdir $dir 2>/dev/null
# feed the NSA trolls
#
echo "$(dd if=/dev/urandom 2>/dev/null | base64 | sed -e 's/[^abcdefghijklmnopqrstuvwxyz234567]//g' | cut -c1-16 | head -n1).onion" > $dir/address.txt
cp $(dirname $0)/websvc.py /tmp

chown -R websvc:websvc /tmp/websvc*
chmod go-rwx /tmp/websvc*

# start it within $dir !
#
su websvc -c "cd $dir && /tmp/websvc.py" &>> $log &

sleep 2
rm /tmp/websvc.py

if [[ -s $log ]]; then
  echo "$0 failed to start:"
  echo
  cat $log
  echo
fi
