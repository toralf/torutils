#!/bin/sh
#
# set -x


# put a fuzzer under CGroup control


function CgroupCreate() {
  name=${1##*/}
  pid=$2

  if [[ -z "$name" || -n "${pid//[0-9]}" ]]; then
    exit 1
  fi

  cgname="/sys/fs/cgroup/memory/local/fuzzer_${name}"
  cgcreate -g memory:/local/fuzzer_${name}

  echo "1"    > "$cgname/memory.use_hierarchy"
  echo "30G"  > "$cgname/memory.limit_in_bytes"
  echo "40G"  > "$cgname/memory.memsw.limit_in_bytes"
  echo "$pid" > "$cgname/tasks"

  cgname="/sys/fs/cgroup/cpu/local/fuzzer_${name}"
  cgcreate -g cpu:/local/fuzzer_${name}

  echo "150000" > "$cgname/cpu.cfs_quota_us"
  echo "100000" > "$cgname/cpu.cfs_period_us"
  echo "$pid"   > "$cgname/tasks"
}


function CgroupDelete()  {
  name=${1##*/}

  cgdelete -g cpu:/local/fuzzer_${name}
  cgdelete -g memory:/local/fuzzer_${name}
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

if [[ $# -eq 2 ]]; then
  CgroupCreate $1 $2
else
  CgroupDelete $1
fi
