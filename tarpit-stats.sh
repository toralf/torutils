#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: print number of unique IPvx addresses per network block of tarpit set(s)

# call:
#   cat ~/tmp/tor-relays/fw/*/torutils-tarpit-v4 | NETMASK=16 ~/devel/torutils/tarpit-stats.sh | head -n 40
#   NETMASK=56 /opt/torutils/tarpit-stats.sh </var/tmp/torutils-tarpit-v6

aggregate_ip() {
  # input is <ip> timeout <int>
  cut -f 1 -d ' ' |
    sort -u |
    python3 -c "
import signal, sys, ipaddress
from collections import Counter

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

user_prefix = '$prefix'
counter = Counter()

for line in sys.stdin:
    if not line.strip():
        continue

    parts = line.strip().split()
    if parts:
        ip_obj = ipaddress.ip_address(parts[0])

        # defaults (24 for IPv4, 48 for IPv6)
        if user_prefix:
            p = int(user_prefix)
        else:
            p = 24 if ip_obj.version == 4 else 48

        net = ipaddress.ip_network(f'{parts[0]}/{p}', strict=False).compressed
        counter[net] += 1

for net, count in counter.most_common():
    print(f'{count:7} {net}')
"
}

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

prefix="${NETMASK:-${1-}}"
aggregate_ip
