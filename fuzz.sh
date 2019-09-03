#!/bin/bash
#
# set -x

# fuzz testing of Tor software as mentioned in
# https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md

mailto="torproject@zwiebeltoralf.de"

# preparation steps at Gentoo Linux:
#
# (I) install AFL
#
# emerge --update sys-devel/clang app-forensics/afl
#
# (II) clone repos
#
# cd ~
# git clone https://github.com/jwilk/recidivm
# git clone https://git.torproject.org/chutney.git
# git clone https://git.torproject.org/fuzzing-corpora.git
# git clone https://git.torproject.org/tor.git
#
# (III) build fuzzers:
#
# fuzz.sh -u
#
# (IV) get/check memory limit (add 50M at the highest value as suggested by recidivm upstream)
#
# cd ~/tor; for i in $(ls ./src/test/fuzz/fuzz-* 2>/dev/null); do echo $(../recidivm/recidivm -v -u M $i 2>&1 | tail -n 1) $i ; done | sort -n
#
# (V) start one fuzzer:
#
# fuzz.sh -s 1


function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-ac] [-f '<fuzzer(s)>'] [-s <number>] [-u]"
  echo
  exit 0
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
        if [[ -n "$(ls $d/*.tbz2 2>/dev/null)" ]]; then
          echo " $d *has* findings, keep it"
          if [[ ! -d ~/archive ]]; then
            mkdir ~/archive
          fi
          mv $d ../archive
        else
          rm -rf $d
        fi
      fi
    fi
  done
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

      # already anything reported ?
      #
      if [[ -f $d/$tbz2 && $tbz2 -ot $d/$i ]]; then
        continue
      fi

      (
        echo "verify it with '$(basename $( ls ~/work/$d/fuzz* ) ) < file' before reporting it to tor-security@lists.torproject.org"
        echo
        cd $d                             &&\
        tar -cjpf $tbz2 ./$i 2>&1         &&\
        uuencode $tbz2 $(basename $tbz2)
      ) |\
      mail -s "$(basename $0) $i in $d" $mailto -a ""
    done
  done
}


#
#
function LogFilesCheck() {
  cd ~/work

  for d in $( ls -1d ./20??????-??????_* 2>/dev/null )
  do
    log=$(cat $d/fuzz.log 2>/dev/null)
    if [[ -f $log ]]; then
      grep -H 'PROGRAM ABORT :' $log
    fi
  done
}


# spin up new fuzzer(s)
#
function startFuzzer()  {
  f=$1

  # input data file for the fuzzer
  #
  idir=$TOR_FUZZ_CORPORA/$f
  if [[ ! -d $idir ]]; then
    echo " idir not found: $idir"
    return
  fi

  # output directory: timestamp + git commit id + fuzzer name
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
  nohup nice /usr/bin/afl-fuzz -i $idir -o $odir -m 100 $dict -- $exe &>$odir/fuzz.log &
  pid="$!"
  echo "$pid" > $odir/fuzz.pid
  echo
  echo " started $f pid=$pid odir=$odir"
  echo
}


# update Tor fuzzer software stack
#
function update_tor() {
  echo " update deps ..."

  cd $RECIDIVM_DIR
  git pull
  make

  cd $CHUTNEY_PATH
  git pull

  cd $TOR_FUZZ_CORPORA
  git pull

  cd $TOR_DIR
  git pull

  echo " check broken linker state ..."

  # anything much bigger than 50 indicates a broken (linker) state
  #
  m=$(for i in $(ls ./src/test/fuzz/fuzz-* 2>/dev/null); do echo $(../recidivm/recidivm -v -u M $i 2>/dev/null | tail -n 1); done | sort -n | tail -n 1)
  if [[ -n "$m" ]]; then
    if [[ $m -gt 1000 ]]; then
      make distclean 2>&1
    fi
  fi

  echo " build fuzzers ..."

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    echo " autogen ..."
    ./autogen.sh 2>&1 || return
  fi

  if [[ ! -f Makefile ]]; then
    echo " configure ..."
    #   --enable-expensive-hardening doesn't work
    #
    ./configure 2>&1 || return
  fi

  # https://trac.torproject.org/projects/tor/ticket/29520
  #
  echo " make ..."
  make micro-revision.i 2>&1 || return

  make fuzzers 2>&1 || return
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
lck=~/.lock
if [[ -s $lck ]]; then
  echo " found old lock file"
  ls -l $lck
  tail -v $lck
  kill -0 $(cat $lck) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo " valid, exiting ..."
    exit 1
  else
    echo " stalled, continuing ..."
    echo
  fi
fi
echo $$ > $lck

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

while getopts acHhlf:s:u\? opt
do
  case $opt in
    a)
      archiveFindings
      ;;
    c)
      checkForFindings
      ;;
    f)
      for f in $OPTARG
      do
        startFuzzer $f
      done
      ;;
    l)
      LogFilesCheck
      ;;
    s)
      # spin up $OPTARG arbitrarily choosen fuzzers
      #
      fuzzers=""
      for f in $(ls $TOR_FUZZ_CORPORA 2>/dev/null)
      do
        if [[ -x $TOR_DIR/src/test/fuzz/fuzz-$f ]]; then
          fuzzers="$fuzzers $f"
        fi
      done
      echo $fuzzers | xargs -n 1 | shuf -n $OPTARG | while read f; do startFuzzer $f; done
      ;;
    u)
      update_tor
      ;;
    *)
      Help
      ;;
  esac
done

rm $lck
