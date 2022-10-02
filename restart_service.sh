#!/bin/bash
#set -x

# works under Gentoo Linxu and OpenRC

while :
do
  if [[ "$(/sbin/runlevel)" = "N 3" ]]; then
    for s in ssh tor tor2
    do
      /sbin/rc-service -qq $s status
      if [[ $? -eq 32 ]]; then
        echo "$0: restart crashed $s"
        /sbin/rc-service $s zap start
      fi
    done
  fi
  sleep 10
done
