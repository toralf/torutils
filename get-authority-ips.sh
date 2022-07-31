#!/bin/bash
# set -x


# create input for firewall allowlist, eg.:   get-authority-ips.sh | grep -F '.' | xargs


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' |\
tee $tmpfile |\
jq -cr '.relays[].a[0]' |\
sort

jq -cr '.relays[].a[1]' $tmpfile |\
grep -v null |\
tr -d '][' |\
sort

rm $tmpfile
