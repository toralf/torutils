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

  cgcreate -g memory:/local/fuzzer_${name}
  cgset -r memory.use_hierarchy=1 -r memory.limit_in_bytes=30G -r memory.memsw.limit_in_bytes=40G -r memory.tasks=$$ fuzzer_${name}

  cgcreate -g cpu:/local/fuzzer_${name}
  cgset -r cpu.cfs_quota_us=150000 -r cpu.cfs_period_us=100000 -r cpu.tasks=$$ fuzzer_${name}
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
