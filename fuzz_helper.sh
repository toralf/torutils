#!/bin/sh
#
# set -x


# put a fuzzer under CGroup control


function CgroupCreate() {
  local name=/local/fuzzer_${1##*/}
  local pid=$2

  cgcreate -g memory:$name -g cpu:$name
  cgset -r memory.use_hierarchy=1           $name
  cgset -r memory.limit_in_bytes=30G        $name
  cgset -r memory.memsw.limit_in_bytes=40G  $name
  echo "$pid" > /sys/fs/cgroup/memory/$name/tasks

  cgset -r cpu.cfs_quota_us=150000  $name
  cgset -r cpu.cfs_period_us=100000 $name
  echo "$pid" > /sys/fs/cgroup/cpu/$name/tasks
}


function CgroupDelete()  {
  local name=/local/fuzzer_${1##*/}

  cgdelete -g memory:$name -g cpu:$name
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

if [[ $# -eq 2 ]]; then
  if [[ "${2//[0-9]}" ]]; then
    exit 1
  fi
  CgroupCreate $1 $2
else
  CgroupDelete $1
fi
