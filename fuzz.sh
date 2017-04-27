#!/bin/bash
#
# set -x

# wrapper of common commands to fuzz test of Tor
#

mailto="torproject@zwiebeltoralf.de"

# preparation:
#
# echo "sys-devel/llvm clang" >> /etc/portage/package.use/llvm
# emerge --update sys-devel/clang
#
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
# git clone https://git.torproject.org/chutney.git
#
# <install recidivm>
#
# $ for i  in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm-0.1.1/recidivm -v $i 2>&1 | tail -n 1) $i ;  done | sort
# 40880663 ./tor/src/test/fuzz/fuzz-iptsv2
# 40880757 ./tor/src/test/fuzz/fuzz-consensus
# 40880890 ./tor/src/test/fuzz/fuzz-extrainfo
# 40885159 ./tor/src/test/fuzz/fuzz-hsdescv2
# 40885224 ./tor/src/test/fuzz/fuzz-http
# 40888156 ./tor/src/test/fuzz/fuzz-descriptor
# 40897371 ./tor/src/test/fuzz/fuzz-microdesc
# 40955570 ./tor/src/test/fuzz/fuzz-vrs

function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-a] [-f '<fuzzer(s)>'] [-k] [-s] [-u]"
  echo
}


function kill_fuzzers()  {
  pkill "fuzz-"
}


# update Tor and its build/test dependencies
#
function update() {
  cd $CHUTNEY_PATH || return 1
  git pull -q

  cd $TOR_FUZZ_CORPORA || return 1
  git pull -q

  cd $TOR_DIR || return 1
  before=$(git describe)
  git pull -q
  after=$(git describe)

  if [[ "$1" = "force" || "$before" != "$after" || ! -f ./configure || ! -f Makefile || ! -f ./src/or/tor || -z "$(ls ./src/test/fuzz/fuzz-* 2> /dev/null)" ]]; then
    make distclean
    ./autogen.sh || return $?
    CC="afl-clang" ./configure --config-cache --disable-gcc-hardening || return $?
    AFL_HARDEN=1 make -j $N fuzzers && make test-fuzz-corpora
    return $?
  fi
}


# spin up fuzzers
#
function startup()  {
  if [[ ! -d ~/work ]]; then
    mkdir ~/work
  fi

  commit=$( cd ~/tor && git describe | cut -f2 -d'g' )
  timestamp=$( date +%Y%m%d-%H%M%S )

  cd ~

  for f in $fuzzers
  do
    exe=~/tor/src/test/fuzz/fuzz-$f
    if [[ ! -x $exe ]]; then
      echo "fuzzer not found: $exe"
      continue
    fi

    odir="./work/${timestamp}_${commit}_${f}"
    mkdir -p $odir || continue

    nohup nice afl-fuzz -i ${TOR_FUZZ_CORPORA}/$f -o $odir -m 50000000 -- $exe &>$odir/log &
    sleep 1
  done
}


# check for crashes and archive the old results (mostly hangs)
#
function archive()  {
  cd ~/work || return 1
  ls -1d 201?????-??????_???????_* 2> /dev/null |\
  while read d
  do
    out=$(mktemp /tmp/crashesXXXXXX)
    ls -l $d/crashes/* 1> $out 2> /dev/null

    if [[ -s $out ]]; then
      a=~/archive/$d.tbz2
      if [[ ! -d ~/archive ]]; then
        mkdir ~/archive
      fi
      tar -cjpf $a $d &>> $out
      (cat $out; uuencode $a $(basename $a)) | timeout 120 mail -s "fuzz crashes in $d" $mailto
    fi

    rm -rf $d $out
  done
}


#######################################################################
#
# main
#

#N=$(expr 11 - $(cut -f3 -d' ' /proc/loadavg | cut -f1 -d'.'))  # parallel jobs
N=2

if [[ $# -eq 0 ]]; then
  Help
  exit 0
fi

if [[ -f ~/.lock ]]; then
  echo "found lock file"
  exit 1
fi

touch ~/.lock

export CHUTNEY_PATH=~/chutney/
export TOR_DIR=~/tor/
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora/

# fuzzers contains targets like "http consensus extrainfo"
#
fuzzers=$( ls ${TOR_FUZZ_CORPORA} | sort --random-sort | head -n $N | xargs )

log=$(mktemp /tmp/fuzzXXXXXX)
while getopts af:hksuU\? opt
do
  case $opt in
    a)  kill_fuzzers
        archive
        ;;
    f)  fuzzers="$OPTARG"
        startup
        ;;
    k)  kill_fuzzers
        ;;
    s)  startup
        ;;
    u|U)
        kill_fuzzers
        update $([[ $opt = "U" ]] && echo "force") &> $log
        rc=$?
        if [[ $rc -ne 0 ]]; then
          echo rc=$rc
          echo
          cat $log
          echo
          break
        fi
        ;;
    *)  Help
        break
        ;;
  esac
done
rm -f $log

rm ~/.lock

exit 0
