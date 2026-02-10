#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: logic to handle different hostmasks than the corresponding "${netmask}" in ipv6-rules.sh

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type ipset jq >/dev/null

jobs=$((1 + $(nproc) / 2)) # parallel jobs of adding entries to an ipset

# Hetzner provides a /64 hostmask
ipset list -n ${1-} |
  grep "^tor-ddos6-" |
  while read -r s; do
    ipset list $s |
      sed '1,8d' |
      grep "^2a01:4f[89]" |
      cut -f 1-5 -d ':' -s |
      cut -f 1-4 -d ':' |
      sort -u |
      xargs -r -P $jobs -I{} ipset add $s {}::/64 -exist
  done
