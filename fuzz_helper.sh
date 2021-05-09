#!/bin/sh
#
# set -x


# put given fuzzer PID under CGroup control


function CgroupCreate() {
  local name=$1
  local pid=$2

  # use cgroup v1 if available
  if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
    return 0
  fi

  cgcreate -g cpu,memory:$name

  cgset -r cpu.cfs_quota_us=150000          $name
  cgset -r memory.limit_in_bytes=20G        $name
  cgset -r memory.memsw.limit_in_bytes=30G  $name

  for i in cpu memory
  do
    echo      1 > /sys/fs/cgroup/$i/$name/notify_on_release
    echo "$pid" > /sys/fs/cgroup/$i/$name/tasks
  done
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

if [[ -z "$1" ]]; then
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "wrong # of args"
  exit 1
fi

if [[ "${2//[0-9]}" ]]; then
  echo "arg 2 not an integer"
  exit 1
fi

CgroupCreate local/fuzzer_${1##*/} $2
