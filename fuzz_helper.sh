#!/bin/sh
#
# set -x


# put a fuzzer under CGroup control


function Cgroup() {
  dir=${1##*/}
  pid=$2

  if [[ -z "$dir" || -n "${pid//[0-9]}" ]]; then
    exit 1
  fi

  cgdir="/sys/fs/cgroup/memory/local/fuzzer_$dir"
  if [[ ! -d "$cgdir" ]]; then
    mkdir "$cgdir"
  fi
  echo "1"    > "$cgdir/memory.use_hierarchy"
  echo "30G"  > "$cgdir/memory.limit_in_bytes"
  echo "40G"  > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$pid" > "$cgdir/tasks"

  cgdir="/sys/fs/cgroup/cpu/local/fuzzer_$dir"
  if [[ ! -d "$cgdir" ]]; then
    mkdir "$cgdir"
  fi
  echo "150000" > "$cgdir/cpu.cfs_quota_us"
  echo "100000" > "$cgdir/cpu.cfs_period_us"
  echo "$pid"   > "$cgdir/tasks"
}


#######################################################################
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

Cgroup $1 $2
