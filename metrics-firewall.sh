#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# prints nftables counters and sets formatted for prometheus
# https://github.com/toralf/torutils

set -euf
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

type jq nft >/dev/null

if [[ $# -ne 2 ]]; then
  echo "2 args are expected" >&2
  exit 1
fi

intervall=${1?INTERVALL NOT GIVEN}
if [[ ! $intervall =~ ^[0-9]+$ ]]; then
  echo "intervall is not an integer" >&2
  exit 1
fi

promfile=${2?PROMFILE NOT GIVEN}
if ! touch $promfile; then
  echo "$promfile cannot be accessed" >&2
  exit 1
fi

lockfile="/tmp/$(basename $0).lock"
if [[ -s $lockfile ]]; then
  pid=$(<$lockfile)
  if kill -0 $pid &>/dev/null; then
    exit 0
  else
    echo "ignore lock file, pid=$pid" >&2
  fi
fi
echo $$ >"$lockfile"

trap 'rm -f $lockfile $promfile' INT QUIT TERM EXIT

while :; do
  now=$EPOCHSECONDS

  tmpfile=$(mktemp /$(basename $0)_XXXXXX.tmp)
  {
    # counters
    var="firewall_counter_packets"
    echo -e "# HELP $var nftables named counter\n# TYPE $var gauge"

    # shellcheck disable=SC2034
    nft -s list tables |
      while read -r keyword family table; do
        nft -s list counters $family $table |
          grep -E "^\s+counter .* {" |
          awk '{ print $2 }' |
          while read -r counter; do
            IFS='_' read -r resource ipver ext <<<$counter
            packets=$(
              nft list counter $family $table $counter |
                grep -E "^\s+packets .* bytes .*" |
                awk '{ print $2 }'
            )
            echo "$var{family=\"$family\",table=\"$table\",resource=\"$resource\",ipver=\"${ipver:-x}\",ext=\"${ext:-x}\"} $packets"
          done
      done

    # sets
    var="firewall_set_size"
    echo -e "# HELP $var nftables set size\n# TYPE $var gauge"

    # shellcheck disable=SC2034
    nft -s list tables |
      while read -r keyword family table; do
        nft -st list sets $family $table |
          grep -E "^\s+set .* {" |
          awk '{ print $2 }' |
          while read -r set; do
            IFS='_' read -r resource ipver ext <<<$set
            n=$(
                nft -j -ns list set $family $table $set |
                  jq '.nftables[].set.elem // [] | length'
              )
            echo "$var{family=\"$family\",table=\"$table\",resource=\"$resource\",ipver=\"${ipver:-x}\",ext=\"${ext:-x}\"} $n"
          done
      done
  } >$tmpfile
  chmod a+r $tmpfile
  mv $tmpfile $promfile

  if ((intervall == 0)); then
    break
  fi
  diff=$((EPOCHSECONDS - now))
  if ((diff < intervall)); then
    sleep $((intervall - diff))
  fi
done
