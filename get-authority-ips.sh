#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# create input for firewall allowlist, eg.:   get-authority-ips.sh | grep -F '.' | xargs


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - |
jq -cr '.relays[].a[0,1]' |
grep -v null |
tr -d '][' |
sort -n
