#!/bin/bash
# set -x


# create input for firewall allowlist, eg.:   get-authority-ips.sh | grep -F '.' | sort | xargs


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

curl -s 'https://onionoo.torproject.org/details?fields=nickname,flags' -o - |\
jq -cr '.relays[] | select ( .flags as $flags | "Authority" | IN($flags[]) ) | .nickname' |\
while read -r nick
do
  curl -s "https://onionoo.torproject.org/summary?search=$nick" -o - |\
  tee $tmpfile |\
  jq -cr '.relays[].a[0]'

  jq -cr '.relays[].a[1]' $tmpfile |\
  grep -v null |\
  tr -d ']['
done

rm $tmpfile
