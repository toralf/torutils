#!/bin/sh
#
#set -x

# unlock a remote ext4-fs encrypted Tor data directory
#

# typical call: ./unlock_tor.sh unlock start
#
# before run once: ./unlock_tor.sh prepare
#

# one time preparation
#
function Prepare()  {
  echo "0x$(head -c 16 /dev/urandom | xxd -p)" > $ldir/.cryptoSalt  &&\
  pwgen -s 32 -1 | head -n1 > $ldir/.cryptoPass

  return $?
}


# copy the salt to the Tor relay (/tmp is a tmpfs == secure delete)
# the password itself will never leave this local system
#
function Unlock() {
  if [[ ! -f $ldir/.cryptoSalt || ! -f $ldir/.cryptoPass ]]; then
    echo "salt and/or pw file not found"
    return 1
  fi

  scp $ldir/.cryptoSalt $host:/tmp || return 2
  cat $ldir/.cryptoPass | ssh $user@$host "sudo -u tor e4crypt add_key -S \$(cat /tmp/.cryptoSalt) $rdir; rm /tmp/.cryptoSalt"

  return $?
}

# this is the OpenRC variant
#
function Init() {
   ssh $user@$host "sudo /etc/init.d/tor $*"
}


#######################################################################
#
host="mr-fox"           # Tor relay
user="tfoerste"         # remote user (needs sudo rights !)
ldir=~/hetzner/$host    # local dir
rdir=/var/lib/tor/data  # remote dir

while [[ $# -gt 0 ]]
do
  opt=$1
  shift

  case $opt in
    prepare)  echo -n "you're sure ? (y/N) :"
              read dummy
              if [[ "$dummy" = "y" ]]; then
                Prepare
              fi
              ;;
    unlock)   Unlock
              ;;
    start|stop|restart) Init $opt
              ;;
    *)        echo "go out !"
              exit 1
              ;;
  esac

  if [[ $? -ne 0 ]]; then
    exit 2
  fi
done
