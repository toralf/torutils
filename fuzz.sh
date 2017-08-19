#!/bin/bash
#
# set -x

# wrapper of common commands to fuzz test of Tor
# see https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md

mailto="torproject@zwiebeltoralf.de"

# preparation (Gentoo Linux way):
#
# echo "sys-devel/llvm clang" >> /etc/portage/package.use/llvm
# emerge --update sys-devel/clang
#
# cd ~
#
# <install recidivm>: https://jwilk.net/software/recidivm
#
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
# git clone https://git.torproject.org/chutney.git
#
#
# for i  in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm-0.1.1/recidivm -v $i -u M 2>&1 | tail -n 1) $i ;  done | sort -n
# 42 ./tor/src/test/fuzz/fuzz-iptsv2
# 42 ./tor/src/test/fuzz/fuzz-consensus
# 42 ./tor/src/test/fuzz/fuzz-extrainfo
# 42 ./tor/src/test/fuzz/fuzz-hsdescv2
# 42 ./tor/src/test/fuzz/fuzz-http
# 42 ./tor/src/test/fuzz/fuzz-descriptor
# 42 ./tor/src/test/fuzz/fuzz-microdesc
# 42 ./tor/src/test/fuzz/fuzz-vrs

function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-a] [-f '<fuzzer(s)>'] [-k] [-u]"
  echo
  exit 0
}


function kill_fuzzers()  {
  pkill "fuzz-"
}


# update build/test dependencies
#
function update_tor() {
  cd $CHUTNEY_PATH
  git pull -q

  cd $TOR_FUZZ_CORPORA
  git pull -q

  cd $TOR_DIR
  before=$( git describe )
  git pull -q
  after=$( git describe )

  if [[ "$before" != "$after" ]]; then
    make distclean || return $?
    ./autogen.sh || return $?
  fi

  if [[ ! -f Makefile ]]; then
    ./configure || return $?    # --enable-expensive-hardening
  fi

  make -j $N fuzzers || return $?
}


# spin up fuzzers
#
function startup()  {
  cd $TOR_DIR
  cid=$( git describe | sed 's/.*\-g//g' )

  cd ~
  for f in $fuzzers
  do
    exe=$TOR_DIR/src/test/fuzz/fuzz-$f
    if [[ ! -x $exe ]]; then
      echo "fuzzer not found: $exe"
      continue
    fi

    timestamp=$( date +%Y%m%d-%H%M%S )

    odir=~/work/${timestamp}_${cid}_${f}
    mkdir -p $odir
    if [[ $? -ne 0 ]]; then
      continue
    fi

    nohup nice afl-fuzz -i ${TOR_FUZZ_CORPORA}/$f -o $odir -m 50 -- $exe &>$odir/log &

    # needed for a unique output dir if the same fuzzer
    # runs more than once at the same time
    #
    sleep 1

    grep -A 10 -F '[-]' $odir/log && ls -l $odir/log
  done
}


# check for findings and archive them
#
function archive()  {
  if [[ ! -d ~/work ]]; then
    return
  fi

  ls -1d ~/work/201?????-??????_?????????_* 2>/dev/null |\
  while read d
  do
    for issue in "crashes"    # "hang" gives too much false positives with non-max-CPU governor and the the overall load at this machine
    do
      out=$(mktemp /tmp/${issue}_XXXXXX)
      ls -l $d/$issue/* 1>$out 2>/dev/null  # "/*" forces an error and an empty stdout

      if [[ -s $out ]]; then
        if [[ ! -d ~/archive ]]; then
          mkdir ~/archive
        fi
        b=$(basename $d)
        a=~/archive/${issue}_$b.tbz2
        tar -cjpf $a $b &>>$out
        if [[ "$issue" = "crashes" ]]; then
          (cat $out; uuencode $a $(basename $a)) | timeout 120 mail -s "fuzz $issue in $b" $mailto
        fi
      fi
      rm $out
    done
    rm -rf $d
  done
}


#######################################################################
#
# main
#
if [[ $# -eq 0 ]]; then
  Help
fi

if [[ -f ~/.lock ]]; then
  echo "found lock file ~/.lock"
  exit 1
fi
touch ~/.lock

# paths to the sources
#
export CHUTNEY_PATH=~/chutney/
export TOR_DIR=~/tor/
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora/

# https://github.com/mirrorer/afl/blob/master/docs/env_variables.txt
#
export CC="afl-gcc"
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_EXIT_WHEN_DONE=1

while getopts af:hku opt
do
  case $opt in
    a)  archive
        ;;
    f)  if [[ $OPTARG =~ [[:digit:]] ]]; then
          fuzzers=$( ls ${TOR_FUZZ_CORPORA} 2>/dev/null | sort --random-sort | head -n $OPTARG | xargs )
        else
          fuzzers="$OPTARG"
        fi
        startup
        ;;
    k)  kill_fuzzers
        ;;
    u)  kill_fuzzers
        log=$(mktemp /tmp/fuzz_XXXXXX)
        update_tor &>$log
        rc=$?
        if [[ $rc -ne 0 ]]; then
          echo rc=$rc
          ls -l $log
          exit $rc
        fi
        rm -f $log
        ;;
    *)  Help
        ;;
  esac
done

rm ~/.lock

exit 0
