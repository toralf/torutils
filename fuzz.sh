#!/bin/bash
#
# set -x

# fuzz testing of Tor software as mentioned in
# https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md

mailto="torproject@zwiebeltoralf.de"

# preparation steps at Gentoo Linux:
#
# (I)
#
# echo "sys-devel/llvm clang" >> /etc/portage/package.use/llvm
# emerge --update sys-devel/clang app-forensics/afl
#
# (II)
#
# cd ~
# git clone https://github.com/jwilk/recidivm
# git clone https://git.torproject.org/chutney.git
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
#
# (III)
#
# for i  in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm/recidivm -v $i -u M 2>&1 | tail -n 1) $i ;  done | sort -n
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
function archive()  {
  if [[ ! -d ~/work ]]; then
    mkdir ~/work
  fi

  if [[ ! -d ~/archive ]]; then
    mkdir ~/archive
  fi

  ls -1d ~/work/201?????-??????_* 2>/dev/null |\
  while read d
  do
    b=$(basename $d)

    for i in crashes hangs
    do
      if [[ -n "$(ls $d/$i 2>/dev/null)" ]]; then
        tbz2=~/archive/${i}_$b.tbz2
        (tar -cjvpf $tbz2 $d/$i 2>&1; uuencode $tbz2 $(basename $tbz2)) | mail -s "fuzz $i found in $b" $mailto
      fi
    done
    rm -rf $d
  done
}


# update Torand its dependencies
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

  # eg. something like "268435456 ./tor/src/test/fuzz/fuzz-vrs" indicates a broken (link) state
  #
  m=$(for i in ./src/test/fuzz/fuzz-*; do echo $(../recidivm/recidivm -v $i -u M 2>&1 | tail -n 1) $i; done | sort -n | tail -n 1 | cut -f1 -d ' ')
  if [[ $m -gt 1000 ]]; then
    make distclean
  fi

  if [[ ! -x ./configure ]]; then
    ./autogen.sh || return 1
  fi

  if [[ ! -f Makefile ]]; then
    # --enable-expensive-hardening doesn't work b/c hardened GCC was built with USE="(-sanitize)"
    #
    ./configure || return 1
  fi

  make -j 1 fuzzers || return 1

  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.out)
  make -j 1 test &> $tmpfile
  rc=$?
  if [[ $rc -ne 0 ]]; then
    cat $tmpfile | mail -s "make test failed with rc=$rc" $mailto
  fi
  rm $tmpfile
}


# spin up fuzzers
#
function startup()  {
  cd $TOR_DIR
  cid=$( git describe | sed 's/.*\-g//g' )

  cd ~
  for f in $fuzzers
  do
    exe="$TOR_DIR/src/test/fuzz/fuzz-$f"
    if [[ ! -x $exe ]]; then
      echo "fuzzer not found: $exe"
      continue
    fi

    idir=$TOR_FUZZ_CORPORA/$f
    if [[ ! -d $idir ]]; then
      echo "idir not found: $idir"
      continue
    fi

    timestamp=$( date +%Y%m%d-%H%M%S )
    odir=~/work/${timestamp}_${cid}_${f}
    mkdir -p $odir
    if [[ $? -ne 0 ]]; then
      continue
    fi

    dict="$TOR_DIR/src/test/fuzz/dict/$f"
    if [[ -e $dict ]]; then
      dict="-x $dict"
    else
      dict=""
    fi

    nohup nice /usr/bin/afl-fuzz -i $idir -o $odir $dict -m 50 -- $exe &>$odir/log &

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

if [[ -f ~/.lock ]]; then
  kill -0 $(cat ~/.lock) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "found valid lock file"
    exit 1
  else
    echo "ignore stalled lock file"
  fi
fi
echo $$ > ~/.lock

export RECIDIVM_DIR=~/recidivm
export CHUTNEY_PATH=~/chutney
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora
export TOR_DIR=~/tor

# https://github.com/mirrorer/afl/blob/master/docs/env_variables.txt
#
export CFLAGS="-O2 -pipe -march=native"
export CC="afl-gcc"

# for afl-gcc
#
export AFL_HARDEN=1
export AFL_DONT_OPTIMIZE=1

# for afl-fuzz
#
export AFL_SKIP_CPUFREQ=1
#export AFL_EXIT_WHEN_DONE=1


while getopts af:hku opt
do
  case $opt in
    a)  archive
        ;;
    f)  if [[ $OPTARG =~ ^[[:digit:]] ]]; then
          # this works b/c there're currently 10 fuzzers defined
          #
          fuzzers=$( ls $TOR_FUZZ_CORPORA 2>/dev/null | sort --random-sort | head -n $OPTARG | xargs )
        else
          fuzzers="$OPTARG"
        fi
        startup
        ;;
    k)  # kill the childs spawned by afl-fuzz
    #
        pkill "fuzz-"
        ;;
    u)  log=$(mktemp /tmp/fuzz_XXXXXX)
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
