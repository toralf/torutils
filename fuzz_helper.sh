#!/bin/sh
#
# set -x


# put a fuzzer under CGroup control


function Cgroup() {
  pid=$1

  for i in memory cpu
  do
    d="/sys/fs/cgroup/$i/fuzzer"
    [[ ! -d "$d" ]] && mkdir "$d"
  done

  # upper limit for all fuzzers
  local cgdir="/sys/fs/cgroup/memory/fuzzer"
  echo "20G"    > "$cgdir/memory.limit_in_bytes"
  echo "30G"    > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$pid"   > "$cgdir/tasks"

  local cgdir="/sys/fs/cgroup/cpu/fuzzer"
  echo "100000" > "$cgdir/cpu.cfs_quota_us"
  echo "100000" > "$cgdir/cpu.cfs_period_us"
  echo "$pid"   > "$cgdir/tasks"
}


#######################################################################
#
if [[ "$(whoami)" != "root" ]]; then
  echo "you must be root "
  exit 1
fi

Cgroup $1
