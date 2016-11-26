#!/bin/sh
#
#set -x

# unlock an ext4-fs encrypted remote Tor relay data directory to start Tor
#

# one time preparation
#
function Prepare()  {
  ssh $user@$host "sudo mkdir $rdir; sudo chown tor:tor $rdir; sudo chmod 700 $rdir"

  chmod 600 $ldir/.crypto*                                          &&\
  echo "0x$(head -c 16 /dev/urandom | xxd -p)" > $ldir/.cryptoSalt  &&\
  pwgen -s 32 -1 | head -n1 > $ldir/.cryptoPass                     &&\
  chmod 400 $ldir/.crypto*

  return $?
}


# copy the salt to the Tor relay (/tmp is a tmpfs)
# the password itself will never leave this local system
#
function Unlock() {
  if [[ ! -f $ldir/.cryptoSalt || ! -f $ldir/.cryptoPass ]]; then
    echo "salt and/or pw file not found"
    return 1
  fi

  scp $ldir/.cryptoSalt $host:/tmp || exit 1
  cat $ldir/.cryptoPass | ssh $user@$host 'sudo -u tor e4crypt add_key -S $(cat /tmp/.cryptoSalt) $rdir; rm /tmp/.cryptoSalt'

  return $?
}

# this is the iopenrc variant
#
function Start() {
   ssh $user@$host 'sudo /etc/init.d/tor start'
}


#######################################################################
#
host="mr-fox"           # Tor relay host
user="tfoerste"         # remote user
ldir=~/hetzner/$host    # local dir
rdir=/var/lib/tor/data  # remote dir

while [[ $# -gt 0 ]]
do
  opt=$1
  shift

  case $opt in
    prepare)  Prepare
              ;;
    unlock)   Unlock
              ;;
    start)    Start
              ;;
    *)        echo "go out !"
              exit 1
              ;;
  esac

  if [[ $? -ne 0 ]]; then
    exit 2
  fi
done
