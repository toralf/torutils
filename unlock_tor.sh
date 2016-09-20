#!/bin/sh
#
#set -x

# unlock an ext4-fs encrypted directory and start the Tor daemon
#

ldir=~/hetzner/$host  # local dir

host="mr-fox"         # Tor relay
user="tfoerste"       # remote user

# preparation:
#
# 1.  echo "0x$(head -c 16 /dev/urandom | xxd -p)" > $ldir/.cryptoSalt
# 2.  pwgen -s 32 -1 | head -n1 > $ldir/.cryptoPass
# 3.  create an empty /var/lib/tor/data at the Tor relay, owned by the tor user

if [[ ! -f $ldir/.cryptoSalt || ! -f $ldir/.cryptoPass ]]; then
  echo "files not found"
  exit 1
fi

scp $ldir/.cryptoSalt $host:/tmp
cat $ldir/.cryptoPass | ssh $user@$host 'sudo -u tor e4crypt add_key -S $(cat /tmp/.cryptoSalt) /var/lib/tor/data && sudo /etc/init.d/tor start; rm /tmp/.cryptoSalt'

exit $?

