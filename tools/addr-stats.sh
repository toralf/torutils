#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# goal: count IP addresses per network block

# call:
#   ipset list <ipset name> | sed -e '1,8d' | cut -f 1 -d ' ' | NETMASK=16 ./addr-stats.sh | head
#   nft -j -n list set inet ingress_filter rule4_v6 | jq -r '.nftables[].set.elem[]?.elem.val.concat | @tsv' | awk '{ print $1 }' | ./addr-stats.sh | head
#   nft -j -n list set inet ingress_filter ddos_v4 | jq -r '.nftables[].set.elem[]?.elem.val' | ./addr-stats.sh | head

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
