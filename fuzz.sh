#!/bin/bash
#
# set -x

# fuzz testing of Tor software as mentioned in
# https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md


# preparation steps at Gentoo Linux:
#
# (I) install AFL++
#
# emerge --update sys-devel/clang app-forensics/AFLplusplus
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
}


# archive findings
#
function archiveOrRemove()  {
  cd ~/work

  for d in $(ls -1d ./*_*_20??????-?????? 2>/dev/null)
  do
    is_stopped=1
    pid=$(cat $d/fuzz.pid 2>/dev/null)
    if [[ -n "$pid" ]]; then
      kill -0 $pid 2>/dev/null && is_stopped=0
    fi

    if [[ -z "$pid" || $is_stopped -eq 1 ]]; then
      if [[ -n "$(ls $d/*.tbz2 2>/dev/null)" ]]; then
        echo " $d *has* findings, keep it"
        if [[ ! -d ~/archive ]]; then
          mkdir ~/archive
        fi
        mv $d ../archive
      else
        echo " $d has no findings, just remove it"
        rm -rf $d
      fi
    fi
  done
}


# check for findings
#
function checkForFindings()  {
  cd ~/work

  for d in $(ls -1d ./*_*_20??????-?????? 2>/dev/null)
  do
    if [[ -n "$(grep 'PROGRAM ABORT' $d/fuzz.log)" ]]; then
      tail -v -n 100 $d/fuzz.log | mail -s "$(basename $0) crash in $d" $mailto -a ""
    fi

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
        echo "verify it with 'cd ~/work/$d; ./fuzz-* < ./$i/*' before inform tor-security@lists.torproject.org"
        echo
        cd $d                             &&\
        tar -cjpf $tbz2 ./$i 2>&1         &&\
        uuencode $tbz2 $(basename $tbz2)
      ) | mail -s "$(basename $0) $i in $d" $mailto -a ""
    done
  done
}


#
#
function LogFilesCheck() {
  cd ~/work

  for d in $(ls -1d ./*_*_20??????-?????? 2>/dev/null)
  do
    log=$(cat $d/fuzz.log 2>/dev/null)
    if [[ -f $log ]]; then
      grep -H 'PROGRAM ABORT :' $log
    fi
  done
}


# spin up the given fuzzer
#
function startIt()  {
  fuzzer=${1?:fuzzer ?!}
  idir=${2?:idir ?!}
  odir=${3?:odir ?!}

  # optional: dictionary for the fuzzer
  #
  dict="$TOR_DIR/src/test/fuzz/dict/$fuzzer"
  if [[ -e $dict ]]; then
    dict="-x $dict"
  else
    dict=""
  fi

  exe=~/work/$odir/fuzz-$fuzzer
  if [[ ! -x $exe ]]; then
    echo "no exe found for $fuzzer"
    return 1
  fi

  # value of -m must be bigger than suggested by recidivm,
  nohup nice -n 2 /usr/bin/afl-fuzz -i $idir -o ~/work/$odir -m 100 $dict -- $exe &>>~/work/$odir/fuzz.log &
  pid="$!"

  # put under cgroup control
  sudo $mypath/fuzz_helper.sh $odir $pid || exit $?

  echo "$pid" > ~/work/$odir/fuzz.pid
  echo
  echo " started $fuzzer pid=$pid odir=~/work/$odir"
  echo
}


# spin up new fuzzer(s)
#
function startANewFuzzer()  {
  fuzzer=$1

  # input data file for the fuzzer
  #
  idir=$TOR_FUZZ_CORPORA/$fuzzer
  if [[ ! -d $idir ]]; then
    echo " idir not found: $idir"
    return 1
  fi

  # output directory: timestamp + git commit id + fuzzer name
  #
  cid=$(cd $TOR_DIR; git describe | sed 's/.*\-g//g' )
  odir=${fuzzer}_${cid}_$( date +%Y%m%d-%H%M%S )
  mkdir -p ~/work/$odir || return 2

  # run a copy of the fuzzer b/c git repo is subject of change
  #
  cp $TOR_DIR/src/test/fuzz/fuzz-$fuzzer ~/work/$odir

  startIt $fuzzer $idir $odir
}


# update Tor fuzzer software stack
#
function update_tor() {
  echo " update deps ..."

  cd $RECIDIVM_DIR
  git pull
  make || return 1

  cd $CHUTNEY_PATH
  git pull

  cd $TOR_FUZZ_CORPORA
  git pull

  cd $TOR_DIR
  git pull

  echo " run recidivm to check broken linker state ..."

  # anything much bigger than 50 indicates a broken (linker) state
  #
  m=$(for i in $(ls ./src/test/fuzz/fuzz-* 2>/dev/null); do echo $(../recidivm/recidivm -v -u M $i 2>/dev/null | tail -n 1); done | sort -n | tail -n 1)
  if [[ -n "$m" ]]; then
    if [[ $m -gt 100 ]]; then
      echo " distclean (recidivm gives M=$m) ..."
      make distclean 2>&1
    fi
  fi

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    echo " autogen ..."
    ./autogen.sh 2>&1 || return 2
  fi

  if [[ ! -f Makefile ]]; then
    # use the configre options from the official Gentoo ebuild, but :
    #   - disable coverage, this has a huge slowdown effect
    #   - enable zstd-advanced-apis
    echo " configure ..."
    gentoo_options="
        --prefix=/usr --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu --mandir=/usr/share/man --infodir=/usr/share/info --datadir=/usr/share --sysconfdir=/etc --localstatedir=/var/lib --disable-dependency-tracking --disable-silent-rules --docdir=/usr/share/doc/tor-0.4.3.5 --htmldir=/usr/share/doc/tor-0.4.3.5/html --libdir=/usr/lib64 --localstatedir=/var --enable-system-torrc --disable-android --disable-html-manual --disable-libfuzzer --enable-missing-doc-warnings --disable-module-dirauth --enable-pic --disable-rust --disable-restart-debugging --disable-zstd-advanced-apis --enable-asciidoc --enable-manpage --enable-lzma --enable-libscrypt --enable-seccomp --enable-module-relay --disable-systemd --enable-gcc-hardening --enable-linker-hardening --disable-unittests --disable-coverage --enable-zstd
    "
    override="
        --enable-module-dirauth --enable-zstd-advanced-apis --enable-unittests --disable-coverage
    "
    ./configure $gentoo_options $override || return 3
  fi

  # https://trac.torproject.org/projects/tor/ticket/29520
  #
  echo " make ..."
  make micro-revision.i 2>&1  || return 4
  make -j 9 fuzzers 2>&1      || return 5
}


#######################################################################
#
# main
#
mailto="torproject@zwiebeltoralf.de"

if [[ $# -eq 0 ]]; then
  Help
fi

# do not run this script in parallel
#
lck=~/.lock
if [[ -s $lck ]]; then
  echo " found $lck"
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

cd $(dirname $0)
mypath=$(pwd)


# tool stack

export RECIDIVM_DIR=~/recidivm
export CHUTNEY_PATH=~/chutney
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora
export TOR_DIR=~/tor

export CFLAGS="-O2 -pipe -march=native"

# afl-fuzz

export AFL_HARDEN=1
export AFL_AUTORESUME=1
export AFL_EXIT_WHEN_DONE=1
export AFL_SHUFFLE_QUEUE=1
export AFL_SKIP_CPUFREQ=1

# llvm_mode
export CC="/usr/bin/afl-clang-fast"
export AFL_LLVM_INSTRUMENT=CFG
export AFL_LLVM_INSTRIM=1

while getopts acHhlf:s:u\? opt
do
  case $opt in
    a)  archiveOrRemove
        ;;
    c)  checkForFindings
        ;;
    f)  for fuzzer in $OPTARG
          do
            startANewFuzzer $fuzzer || exit $?
          done
        ;;
    l)  LogFilesCheck
        ;;
    s)  # spin up $OPTARG arbitrarily choosen fuzzers
        #
        fuzzers=""
        for fuzzer in $(ls $TOR_FUZZ_CORPORA 2>/dev/null)
        do
          if [[ -x $TOR_DIR/src/test/fuzz/fuzz-$fuzzer ]]; then
            fuzzers="$fuzzers $fuzzer"
          fi
        done
        echo $fuzzers | xargs -n 1 --no-run-if-empty | shuf -n $OPTARG | while read fuzzer; do startANewFuzzer $fuzzer; done
        ;;
    u)  update_tor || exit $?
        ;;
    *)  Help
        ;;
  esac
done

rm $lck
