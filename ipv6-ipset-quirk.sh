#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# iptables works with hash:ip but not well (enough) with hash:net
# therefore replace all entries of a given CIDR block with one entry (e.g. all /56 with one /64)

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# do not run twice
if pgrep -f $(basename $0) | grep -v $$ | grep -q .; then
  exit 0
fi

type ipset >/dev/null

jobs=$((1 + $(nproc) / 2)) # parallel jobs to mangle an ipset

# Hetzner provides a /64 hostmask for each VPS
ipset list -n ${1-} |
  grep "^tor-ddos6-" |
  while read -r s; do
    entries=$(
      ipset list $s |
        sed '1,8d' |
        awk '{ print $1 }' |
        grep "^2a01:4f[89]" |
        cut -f 1-5 -d ':' -s |
        grep -v -e '/' -e ':$' |
        sort -u
    )

    cut -f 1-4 -d ':' <<<$entries |
      uniq |
      xargs -r -P $jobs -I{} ipset add $s {}::/64 -exist

    xargs -r -P $jobs -I{} ipset del $s {}:: -exist <<<$entries
  done
