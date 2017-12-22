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
# cd ~/tor; for i in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm/recidivm -v $i -u M 2>&1 | tail -n 1) $i ;  done | sort -n
# 46 ./tor/src/test/fuzz/fuzz-consensus
# 46 ./tor/src/test/fuzz/fuzz-descriptor
# 46 ./tor/src/test/fuzz/fuzz-diff
# 46 ./tor/src/test/fuzz/fuzz-diff-apply
# 46 ./tor/src/test/fuzz/fuzz-extrainfo
# 46 ./tor/src/test/fuzz/fuzz-hsdescv2
# 46 ./tor/src/test/fuzz/fuzz-http
# 46 ./tor/src/test/fuzz/fuzz-http-connect
# 46 ./tor/src/test/fuzz/fuzz-iptsv2
# 46 ./tor/src/test/fuzz/fuzz-microdesc
# 46 ./tor/src/test/fuzz/fuzz-vrs

function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-a] [-f '<fuzzer(s)>'] [-k] [-u]"
  echo
  exit 0
}


# keep found issues
#
function checkResult()  {
  if [[ ! -d ~/findings ]]; then
    mkdir ~/findings
  fi

  if [[ ! -d ~/done ]]; then
    mkdir ~/done
  fi

  for d in $(ls -1d ~/work/20??????-??????_* 2>/dev/null)
  do
    # check for findings
    #
    for i in crashes hangs
    do
      tbz2=$d/$i.tbz2
      if [[ -f $tbz2 ]]; then
        continue
      fi

      if [[ -n "$(ls $d/$i 2>/dev/null)" ]]; then
        ( tar -cjpf $tbz2 $d/$i 2>&1; uuencode $tbz2 $(basename $tbz2) ) |\
          mail -s "$(basename $0) catched $i in $(basename $d)" $mailto
      fi
    done

    # keep found issue(s)
    #
    pid=$d/fuzz.pid
    if [[ -s $pid ]]; then
      kill -0 $(cat $pid) 2>/dev/null
      if [[ $? -ne 0 ]]; then
        if [[ -f "$(ls $d/*.tbz2 2>/dev/null)" ]]; then
          echo "$d has findings"
          mv $d ~/findings
        else
          echo "$d is done"
          mv $d ~/done
        fi
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

  # something like "268435456 ./tor/src/test/fuzz/fuzz-vrs" indicates a broken (linker) state
  #
  m=$(for i in ./src/test/fuzz/fuzz-*; do echo $(../recidivm/recidivm -v $i -u M 2>&1 | tail -n 1) $i; done | sort -n | tail -n 1 | cut -f1 -d ' ')
  if [[ $m -gt 1000 ]]; then
    make distclean
  fi

  if [[ ! -x ./configure ]]; then
    ./autogen.sh || return $?
  fi

  if [[ ! -f Makefile ]]; then
    #   --enable-expensive-hardening doesn't work b/c hardened GCC is built with USE="(-sanitize)"
    #
    ./configure CFLAGS="$CFLAGS" CC="$CC" || return $?
  fi

  # target "fuzzers" seems not to build main target before which yields into compile error like
  # "src/or/git_revision.c:14:28: fatal error: micro-revision.i: No such file or directory"
  #
  make -j 1         || return $?
  make -j 1 fuzzers || return $?
}


# spin up new fuzzer(s)
#
function startFuzzer()  {
  if [[ ! -d ~/work ]]; then
    mkdir ~/work
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
    odir=~/work/${timestamp}_${cid}_${f}
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
    echo "started $exe pid=$pid"

    # avoid same timestamp for the same fuzzer
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

# do not run this script in parallel
#
if [[ -f ~/.lock ]]; then
  kill -0 $(cat ~/.lock) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo " found a valid lock file, exiting ..."
    exit 1
  else
    echo " will ignore stalled lock file, continuing ..."
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

while getopts chs:u opt
do
  case $opt in
    c)  checkResult
    ;;

    s)  if [[ $OPTARG =~ ^[[:digit:]] ]]; then
          # this works for up to 10 different fuzzers
          #
          fuzzers=$( ls $TOR_FUZZ_CORPORA 2>/dev/null | sort --random-sort | head -n $OPTARG | xargs )
        else
          fuzzers="$OPTARG"
        fi
        startFuzzer
    ;;

    u)  update_tor || exit $?
    ;;

    *)  Help
    ;;
  esac
done

rm ~/.lock

exit 0
