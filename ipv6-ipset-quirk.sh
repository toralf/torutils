#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: logic to handle different hostmasks than the corresponding "${netmask}" in ipv6-rules.sh

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# do not run twice
if pgrep -f $(basename $0) | grep -v $$ | grep -q .; then
  exit 0
fi

type ipset jq >/dev/null

jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding entries to an ipset

# Hetzner provides a /64 hostmask
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

    # superseed entries of the same /64 CIDR block with one entry
    cut -f 1-4 -d ':' <<<$entries |
      uniq |
      xargs -r -P $jobs -I{} ipset add $s {}::/64 -exist

    # shrink now the ipset by superseeded entries
    xargs -r -P $jobs -I{} ipset del $s {}:: -exist <<<$entries
  done
