#!/bin/sh
#
# set -x


# put a fuzzer under CGroup control


function Cgroup() {
  odir=${1##*/}
  pid=${2//[0-9]}

  if [[ -z "$odir" || -z "$pid" ]]; then
    exit 1
  fi

  for i in memory cpu
  do
    d="/sys/fs/cgroup/$i/fuzzer"
    if [[ ! -d "$d" ]]; then
      mkdir "$d" || exit 1
    fi
  done

  # global upper limits for all fuzzers

  local cgdir="/sys/fs/cgroup/memory/fuzzer"
  echo "10G"    > "$cgdir/memory.limit_in_bytes"
  echo "20G"    > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$pid"   > "$cgdir/tasks"

  local cgdir="/sys/fs/cgroup/cpu/fuzzer"
  echo "900000" > "$cgdir/cpu.cfs_quota_us"
  echo "900000" > "$cgdir/cpu.cfs_period_us"
  echo "$pid"   > "$cgdir/tasks"

  # fuzzer specific limits

  cgdir="/sys/fs/cgroup/cpu/fuzzer/$odir"
  mkdir "$cgdir" || exit 2
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

Cgroup $1 $2
