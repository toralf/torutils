#!/bin/bash
# set -x


set -euf
export LANG=C.utf8


v=$(tor --version | head -n 1 | cut -f2 -d'(' | tr -d '(git\-).')
h=$(su - torproject bash -c 'cd ~torproject/sources/tor; git pull &>/dev/null; git describe HEAD | sed "s,^.*-g,,g"')

if [[ -n $v && -n $h && ! $v =~ $h ]]; then
  echo " $0: $v -> $h"
  emerge -1 net-vpn/tor
  /sbin/rc-service tor  restart
  /sbin/rc-service tor2 restart
fi
