#!/bin/sh
#
# set -x


# put a fuzzer under CGroup control


function CgroupCreate() {
  local name=$1
  local pid=$2

  cgcreate -g cpu,memory:$name

  cgset -r cpu.use_hierarchy=1      $name
  cgset -r cpu.cfs_quota_us=150000  $name
  cgset -r cpu.cfs_period_us=100000 $name
  cgset -r cpu.notify_on_release=1  $name

  cgset -r memory.use_hierarchy=1           $name
  cgset -r memory.limit_in_bytes=30G        $name
  cgset -r memory.memsw.limit_in_bytes=40G  $name
  cgset -r memory.notify_on_release=1       $name

  echo "$pid" > /sys/fs/cgroup/cpu/$name/tasks
  echo "$pid" > /sys/fs/cgroup/memory/$name/tasks
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
