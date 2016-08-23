#!/bin/sh
#
#set -x

#	unlock an ext4-fs encrypted directory and start the Tor daemon
#

user="tfoerste"
host="mr-fox"
ldir=~/hetzner/$host

if [[ ! -f $ldir/.cryptoSalt || ! -f $ldir/.cryptoPass ]]; then
  echo "files not found"
  exit 1
fi

scp $ldir/.cryptoSalt $host:/tmp
cat $ldir/.cryptoPass | ssh $user@$host 'sudo -u tor e4crypt add_key -S $(cat /tmp/.cryptoSalt) /var/lib/tor && sudo /etc/init.d/tor start; rm /tmp/.cryptoSalt'

exit $?

