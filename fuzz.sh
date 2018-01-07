#!/bin/bash
#
# set -x

# fuzz testing of Tor software as mentioned in
# https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md

mailto="torproject@zwiebeltoralf.de"

# preparation steps at Gentoo Linux:
#
# (I) install AFL (as root)
#
# emerge --update sys-devel/clang app-forensics/afl
#
# (II) clone repos
#
# cd ~
# git clone https://github.com/jwilk/recidivm
# git clone https://git.torproject.org/chutney.git
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
#
# (III) build Tor:
#
#/opt/torutils/fuzz.sh -k -a -u
#
# (IV) get/check memory limit
#
# cd ~/tor; for i in ./src/test/fuzz/fuzz-*; do echo $(../recidivm/recidivm -v -u M $i 2>&1 | tail -n 1) $i ; done | sort -n
# 42 ./src/test/fuzz/fuzz-consensus
# 42 ./src/test/fuzz/fuzz-descriptor
# 42 ./src/test/fuzz/fuzz-diff
# 42 ./src/test/fuzz/fuzz-diff-apply
# 42 ./src/test/fuzz/fuzz-extrainfo
# 42 ./src/test/fuzz/fuzz-hsdescv2
# 42 ./src/test/fuzz/fuzz-hsdescv3
# 42 ./src/test/fuzz/fuzz-http
# 42 ./src/test/fuzz/fuzz-http-connect
# 42 ./src/test/fuzz/fuzz-iptsv2
# 42 ./src/test/fuzz/fuzz-microdesc
# 42 ./src/test/fuzz/fuzz-vrs

function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-a] [-f '<fuzzer(s)>'] [-k] [-u]"
  echo
  exit 0
}


# keep found issues
#
function checkResult()  {
  if [[ ! -d ./findings ]]; then
    mkdir ./findings
  fi

  cd ./work

  for d in $(ls -1d ./20??????-??????_* 2>/dev/null)
  do
    log=$d/fuzz.log
    pid=$(cat $d/fuzz.pid 2>/dev/null)

    # kill hanging fuzzers
    #
    if [[ -f $log ]]; then
      let "t = $(date +%s) - $(date +%s -r $log)"
      if [[ $t -gt 86400 ]]; then
        echo
        echo "logfile $log is older than $t seconds (> 1 day)"
        echo
        if [[ -n $pid ]]; then
          echo "will kill process $pid"
          kill $pid
        fi
      fi
    fi

    # check for findings
    #
    for i in crashes hangs
    do
      # prefix archive file name intentionally with $d
      #
      tbz2=$(basename $d)-$i.tbz2
      if [[ -f $d/$tbz2 && -z "$(find $d/$i -newer $d/$tbz2)" || -z "$(ls $d/$i 2>/dev/null)" ]]; then
        continue
      fi

      (
        echo "re-test it like:  $TOR_DIR/src/test/fuzz/fuzz-$(dirname $d | cut -f3 -d'_') < $d/$i/..."
        cd $d && tar -cjpf $tbz2 ./$i 2>&1 && uuencode $tbz2 $(basename $tbz2)
      ) |\
        mail -s "$(basename $0) catched new $i in $d" $mailto -a ''
    done

    # keep found issue(s)
    #
    if [[ -n $pid ]]; then
      kill -0 $pid 2>/dev/null
      if [[ $? -ne 0 ]]; then
        echo
        echo "$d finished"
        if [[ -n "$(ls $d/*.tbz2 2>/dev/null)" ]]; then
          echo "$d *has* findings, kept it"
          mv $d ../findings
        else
          echo "$d has no findings"
          rm -rf $d
        fi
        echo
      fi
    fi

  done
}


# update Tor fuzzer software stack
#
function update_tor() {
  cd $RECIDIVM_DIR
  git pull -q
  make

  cd $CHUTNEY_PATH
  git pull -q

  cd $TOR_FUZZ_CORPORA
  git pull -q

  cd $TOR_DIR
  git pull -q

  # anything much bigger than 50 indicates a broken (linker) state
  #
  m=$(for i in ./src/test/fuzz/fuzz-*; do echo $(../recidivm/recidivm -v -u M $i 2>&1 | tail -n 1); done | sort -n | tail -n 1)
  if [[ $m -gt 100 ]]; then
    make distclean
  fi

  if [[ ! -x ./configure ]]; then
    ./autogen.sh || return $?
  fi

  if [[ ! -f Makefile ]]; then
    #   --enable-expensive-hardening doesn't work b/c hardened GCC is built with USE="(-sanitize)"
    #
    CFLAGS="$CFLAGS" CC="$CC" ./configure || return $?
  fi

  # choose free cpu slots
  #
  if [[ -n "$fuzzers" ]]; then
    j=$(echo $fuzzers | wc -w)
  else
    j="1"
  fi
  # target "fuzzers" seems not to build the make target "main"
  # this yields into compile errors like "src/or/git_revision.c:14:28: fatal error: micro-revision.i: No such file or directory"
  #
  make -j $j         || return $?
  make -j $j fuzzers || return $?
}


# spin up new fuzzer(s)
#
function startFuzzer()  {
  if [[ ! -d ./work ]]; then
    mkdir ./work
  fi

  cd $TOR_DIR
  cid=$( git describe | sed 's/.*\-g//g' )

  cd ~
  for f in $fuzzers
  do
    # the fuzzer itslef
    #
    exe="$TOR_DIR/src/test/fuzz/fuzz-$f"
    if [[ ! -x $exe ]]; then
      echo "fuzzer not found: $exe"
      continue
    fi

    # input data files for the fuzzer
    #
    idir=$TOR_FUZZ_CORPORA/$f
    if [[ ! -d $idir ]]; then
      echo "idir not found: $idir"
      continue
    fi

    # output directory
    #
    timestamp=$( date +%Y%m%d-%H%M%S )
    odir=./work/${timestamp}_${cid}_${f}
    mkdir -p $odir
    if [[ $? -ne 0 ]]; then
      continue
    fi

    # optional: dictionare for the fuzzer
    #
    dict="$TOR_DIR/src/test/fuzz/dict/$f"
    if [[ -e $dict ]]; then
      dict="-x $dict"
    else
      dict=""
    fi

    # fire it up
    #
    nohup nice /usr/bin/afl-fuzz -i $idir -o $odir $dict -m 50 -- $exe &>$odir/fuzz.log &
    pid="$!"
    echo "$pid" > $odir/fuzz.pid
    echo
    echo "started $f pid=$pid odir=$odir"
    echo

    # avoid equal timestamp for the same fuzzer
    #
    sleep 1
  done
}


#######################################################################
#
# main
#
if [[ $# -eq 0 ]]; then
  Help
fi

cd ~ 1>/dev/null

# do not run this script in parallel
#
if [[ -f ./.lock ]]; then
  ls -l ./.lock
  tail -v ./.lock
  kill -0 $(cat ./.lock) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "lock file is valid, exiting ..."
    exit 1
  else
    echo "lock file si stalled, continuing ..."
  fi
fi
echo $$ > ~/.lock

# pathes to sources
#
export RECIDIVM_DIR=~/recidivm
export CHUTNEY_PATH=~/chutney
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora
export TOR_DIR=~/tor

# https://github.com/mirrorer/afl/blob/master/docs/env_variables.txt
#
# for afl-gcc
#
export AFL_HARDEN=1
export AFL_DONT_OPTIMIZE=1
# for afl-fuzz
#
export AFL_SKIP_CPUFREQ=1
export AFL_EXIT_WHEN_DONE=1
export AFL_NO_AFFINITY=1

export CFLAGS="-O2 -pipe -march=native"
export CC="afl-gcc"

while getopts chf:s:u opt
do
  case $opt in
    c)
      checkResult
      ;;
    f)
      # directly specified
      fuzzers="$OPTARG"
      startFuzzer
      ;;
    s)
      # amount given
      fuzzers=$( ls $TOR_FUZZ_CORPORA 2>/dev/null | sort --random-sort | head -n $OPTARG | xargs )
      startFuzzer
      ;;
    u)
      update_tor || exit $?
      ;;
    *)
      Help
      ;;
  esac
done

rm ~/.lock

exit 0
