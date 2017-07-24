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
# <install recidivm> : https://jwilk.net/software/recidivm
#
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
# git clone https://git.torproject.org/chutney.git
#
#
# for i  in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm-0.1.1/recidivm -v $i -u M 2>&1 | tail -n 1) $i ;  done | sort -n
# 38 ./tor/src/test/fuzz/fuzz-iptsv2
# 38 ./tor/src/test/fuzz/fuzz-consensus
# 38 ./tor/src/test/fuzz/fuzz-extrainfo
# 38 ./tor/src/test/fuzz/fuzz-hsdescv2
# 38 ./tor/src/test/fuzz/fuzz-http
# 38 ./tor/src/test/fuzz/fuzz-descriptor
# 38 ./tor/src/test/fuzz/fuzz-microdesc
# 38 ./tor/src/test/fuzz/fuzz-vrs

function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-a] [-f '<fuzzer(s)>'] [-k] [-s] [-u]"
  echo
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
  before=$(git describe)
  git pull -q
  after=$(git describe)

  if [[ ! -f ./configure ]]; then
    ./autogen.sh || return $?
  fi

  if [[ "$before" != "$after" ]]; then
    make distclean 2>/dev/null
  fi

  if [[ ! -f Makefile ]]; then
    ./configure || return $?   # --enable-expensive-hardening
  fi

  make -j $N fuzzers || freturn $?
}


# spin up fuzzers
#
function startup()  {
  cd $TOR_DIR
  commit=$( git describe | sed 's/.*\-g//g' )

  cd ~
  for f in $fuzzers
  do
    exe=$TOR_DIR/src/test/fuzz/fuzz-$f
    if [[ ! -x $exe ]]; then
      echo "fuzzer not found: $exe"
      continue
    fi

    # needed for a unique output dir if the same fuzzer
    # runs more than once at the same time
    sleep 1
    timestamp=$( date +%Y%m%d-%H%M%S )

    odir="./work/${timestamp}_${commit}_${f}"
    mkdir -p $odir
    if [[ $? -ne 0 ]]; then
      continue
    fi

    nohup nice afl-fuzz -i ${TOR_FUZZ_CORPORA}/$f -o $odir -m 50 -- $exe &>$odir/log &
    grep -A 20 'Whoops' $odir/log
  done

  pgrep "afl-fuzz" &>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "didn't found any running fuzzers ?!?"
  fi
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
        tar -cjpf $a $b &>> $out
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
  exit 0
fi

if [[ -f ~/.lock ]]; then
  echo "found lock file ~/.lock"
  exit 1
fi
touch ~/.lock

export AFL_HARDEN=1
export CC="afl-clang"

export CHUTNEY_PATH=~/chutney/
export TOR_DIR=~/tor/
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora/

export AFL_SKIP_CPUFREQ=1

log=$(mktemp /tmp/fuzz_XXXXXX)
while getopts af:hkn:su opt
do
  case $opt in
    a)  kill_fuzzers
        archive
        ;;
    f)  fuzzers="$OPTARG"
        ;;
    k)  kill_fuzzers
        ;;
    n)  fuzzers=$( ls ${TOR_FUZZ_CORPORA} 2> /dev/null | sort --random-sort | head -n $OPTARG | xargs )
        ;;
    s)  startup
        ;;
    u)
        kill_fuzzers
        update_tor &> $log
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
