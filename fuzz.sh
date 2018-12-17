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
# (III) build fuzzers:
#
# /opt/torutils/fuzz.sh -u
#
# (IV) get/check memory limit
#
# cd ~/tor; for i in $(ls ./src/test/fuzz/fuzz-* 2>/dev/null); do echo $(../recidivm/recidivm -v -u M $i 2>&1 | tail -n 1) $i ; done | sort -n
# 41 ./src/test/fuzz/fuzz-consensus
# 41 ./src/test/fuzz/fuzz-descriptor
# 41 ./src/test/fuzz/fuzz-diff
# 41 ./src/test/fuzz/fuzz-diff-apply
# 41 ./src/test/fuzz/fuzz-extrainfo
# 41 ./src/test/fuzz/fuzz-hsdescv2
# 41 ./src/test/fuzz/fuzz-hsdescv3
# 41 ./src/test/fuzz/fuzz-http
# 41 ./src/test/fuzz/fuzz-http-connect
# 41 ./src/test/fuzz/fuzz-iptsv2
# 41 ./src/test/fuzz/fuzz-microdesc
# 41 ./src/test/fuzz/fuzz-socks
# 41 ./src/test/fuzz/fuzz-vrs
#
# (V) start fuzzers:
#
# /opt/torutils/fuzz.sh -s 10


function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-ac] [-f '<fuzzer(s)>'] [-s <number>] [-u]"
  echo
  exit 0
}


# check for findings
#
function checkForFindings()  {
  cd ~/work

  for d in $( ls -1d ./20??????-??????_* 2>/dev/null )
  do
    for i in crashes hangs
    do
      if [[ -z "$(ls $d/$i 2>/dev/null)" ]]; then
        continue
      fi

      tbz2=$(basename $d)-$i.tbz2
      if [[ -f $d/$tbz2 && $tbz2 -ot $d/$i ]]; then
        continue
      fi

      (
        cd $d                             &&\
        tar -cjpf $tbz2 ./$i 2>&1         &&\
        uuencode $tbz2 $(basename $tbz2)
      ) |\
      mail -s "$(basename $0) $i in $d" $mailto -a ""
    done
  done
}


# archive findings
#
function archiveFindings()  {
  cd ~/work

  for d in $( ls -1d ./20??????-??????_* 2>/dev/null )
  do
    pid=$(cat $d/fuzz.pid 2>/dev/null)
    if [[ -n $pid ]]; then
      kill -0 $pid 2>/dev/null
      if [[ $? -ne 0 ]]; then
        echo
        echo "$d finished"
        if [[ -n "$(ls $d/*.tbz2 2>/dev/null)" ]]; then
          echo "$d *has* findings, keep it"
          if [[ ! -d ~/archive ]]; then
            mkdir ~/archive
          fi
          mv $d ../archive
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
  echo "update deps ..."

  cd $RECIDIVM_DIR
  git pull -q
  make

  cd $CHUTNEY_PATH
  git pull -q

  cd $TOR_FUZZ_CORPORA
  git pull -q

  cd $TOR_DIR
  git pull -q
  git describe

  echo "check broken linker state ..."

  # anything much bigger than 50 indicates a broken (linker) state
  #
  m=$(for i in $(ls ./src/test/fuzz/fuzz-* 2>/dev/null); do echo $(../recidivm/recidivm -v -u M $i 2>&1 | tail -n 1); done | sort -n | tail -n 1)
  if [[ -n "$m" ]]; then
    if [[ $m -gt 100 ]]; then
      make distclean
    fi
  else
    echo "can't run recidivm, exiting ..."
    return
  fi

  echo "build fuzzers ..."

  if [[ ! -x ./configure ]]; then
    ./autogen.sh 2>&1 || return
  fi

  if [[ ! -f Makefile ]]; then
    #   --enable-expensive-hardening doesn't work b/c hardened GCC is built with USE="(-sanitize)"
    #
    ./configure 2>&1 || return
  fi

  make fuzzers 2>&1 || return
}


# spin up new fuzzer(s)
#
function startFuzzer()  {
  f=$1

  # input data file for the fuzzer
  #
  idir=$TOR_FUZZ_CORPORA/$f
  if [[ ! -d $idir ]]; then
    echo "idir not found: $idir"
    return
  fi

  # output directory
  #
  cid=$(cd $TOR_DIR; git describe | sed 's/.*\-g//g' )
  odir=~/work/$( date +%Y%m%d-%H%M%S )_${cid}_${f}
  mkdir -p $odir
  if [[ $? -ne 0 ]]; then
    return
  fi

  # run a copy of the fuzzer b/c git repo is subject of change
  #
  cp $TOR_DIR/src/test/fuzz/fuzz-$f $odir
  exe=$odir/fuzz-$f

  # optional: dictionary for the fuzzer
  #
  dict="$TOR_DIR/src/test/fuzz/dict/$f"
  if [[ -e $dict ]]; then
    dict="-x $dict"
  else
    dict=""
  fi

  # fire it up
  #
  nohup nice /usr/bin/afl-fuzz -i $idir -o $odir -m 50 $dict -- $exe &>$odir/fuzz.log &
  pid="$!"
  echo "$pid" > $odir/fuzz.pid
  echo
  echo "started $f pid=$pid odir=$odir"
  echo
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
if [[ -s ~/.lock ]]; then
  ls -l ~/.lock
  tail -v ~/.lock
  kill -0 $(cat ~/.lock) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo " lock file is valid, exiting ..."
    exit 1
  else
    echo " lock file is stalled, continuing ..."
    echo
  fi
fi
echo $$ > ~/.lock

export RECIDIVM_DIR=~/recidivm
export CHUTNEY_PATH=~/chutney
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora
export TOR_DIR=~/tor

# https://github.com/mirrorer/afl/blob/master/docs/env_variables.txt
#
# afl-gcc
#
export AFL_HARDEN=1
#
# afl-fuzz
#
export AFL_SKIP_CPUFREQ=1
export AFL_EXIT_WHEN_DONE=1
export AFL_SHUFFLE_QUEUE=1

export CFLAGS="-O2 -pipe -march=native"
export CC="afl-gcc"

export GCC_COLORS=""

while getopts achf:s:u opt
do
  case $opt in
    a)
      checkForFindings
      archiveFindings
      ;;
    c)
      checkForFindings
      ;;
    f)
      startFuzzer $OPTARG
      ;;
    s)
      # spin up $OPTARG arbitrarily choosen fuzzers
      #
      i=0
      for f in $( ls $TOR_FUZZ_CORPORA 2>/dev/null | sort --random-sort )
      do
        if [[ ! -x $TOR_DIR/src/test/fuzz/fuzz-$f ]]; then
          continue
        fi

        ls -d ~/work/*-*_*_$f &>/dev/null
        if [[ $? -ne 0 ]]; then
          startFuzzer $f
          ((i=i+1))
          if [[ $i -ge $OPTARG ]]; then
            break
          fi
        fi
      done
      ;;
    u)
      update_tor
      ;;
    *)
      Help
      ;;
  esac
done

rm ~/.lock

exit 0
