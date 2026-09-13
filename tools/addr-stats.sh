#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: count unique IP addresses per network block

# call:
#   sort -u ~/tmp/tor-relays/fw/*/torutils-tarpit-v4 | NETMASK=16 ~/devel/torutils/addr-stats.sh | head -n 40
#   ipset list torutils-ddos-v4-443-32 | sed -e '1,8d' | cut -f 1 -d ' '| /opt/torutils/addr-stats.sh | head

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

python3 -c "
import signal, sys, ipaddress
from collections import Counter

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

user_prefix = '${NETMASK:-${1-}}'
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
