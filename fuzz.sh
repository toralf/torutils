#!/bin/bash
# set -x

# fuzz testing of Tor software as mentioned in
# https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md


# preparation steps at Gentoo Linux:
#
# (I) install AFL++
#
# emerge --update sys-devel/clang app-forensics/AFLplusplus
#
# (II) clone Git repositories
#
# cd ~
# git clone https://github.com/jwilk/recidivm
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
# (V) start an arbitrary fuzzer:
#
# fuzz.sh -s 1


function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-afgu] [-r <# of fuzzers to be resumed> ] [-s '<fuzzer name(s)>'|<# of new fuzzers>]"
  echo
}



function __listWorkDirs() {
  ls -1d $workdir/*_20??????-??????_* 2>/dev/null
}


function __getPid() {
  awk '/fuzzer_pid/ { print $3 }' $1/fuzzer_stats 2>/dev/null
}


# 0 = it is runnning
# 1 = it is stopped
function __isRunning()  {
  pid=$(__getPid $1)
  if [[ -n "$pid" ]]; then
    kill -0 $pid 2>/dev/null
    return $?
  fi

  return 1
}


function archiveOrDone()  {
  for d in $(__listWorkDirs)
  do
    __isRunning $d && continue

    logfile=$d/fuzz.log
    if [[ ! -f $logfile ]]; then
      continue
    fi

    # indicate that the fuzzer isn't running but keep the graphs
    rm -f $plotdir/${d##*/}/index.html

    tail -n 10 $logfile | grep -m 1 "^\[-\] PROGRAM ABORT :"
    if [[ $? -eq 0 ]]; then
      echo
      echo " aborted: $d"
      mv $d $abortdir
      echo
      continue
    fi

    # act only at the last abort reason
    tac $logfile | grep -m 1 "^+++ Testing aborted .* +++" | grep "^+++ Testing aborted programmatically +++"
    rc=$?
    if [[ $rc -eq 0 ]]; then
      echo
      echo " done: $d"
      mv $d $donedir
      echo
    elif [[ -n "$(ls $d/{crashes,hangs}/* 2>/dev/null)" ]]; then
      echo
      echo " archive: $d"
      mv $d $archdir
      echo
    fi
  done
}


function lookForFindings()  {
  for d in $(__listWorkDirs)
  do
    for i in crashes hangs
    do
      if [[ -z "$(ls $d/$i 2>/dev/null)" ]]; then
        continue
      fi

      tbz2=$(basename $d)-$i.tbz2

      # already reported ?
      #
      if [[ -f $d/$tbz2 && $tbz2 -ot $d/$i ]]; then
        continue
      fi

      (
        echo "verify $i it with 'cd $d; ./fuzz-* < ./$i/*' then inform tor-security@lists.torproject.org"
        echo
        cd $d                             &&\
        tar -cjpf $tbz2 ./$i 2>&1         &&\
        uuencode $tbz2 $(basename $tbz2)
      ) | mail -s "$(basename $0) $i in $d" $mailto -a ""
    done
  done
}


function gnuplot()  {
  for d in $(__listWorkDirs)
  do
    __isRunning $d || continue
    local b=$(basename $d)
    local destdir=$plotdir/$b
    if [[ ! -d $destdir ]]; then
      mkdir $destdir
    fi
    afl-plot $d $destdir &>/dev/null
  done
}


# spin up the given fuzzer
function startIt()  {
  fuzzer=${1?:fuzzer ?!}
  idir=${2?:idir ?!}
  odir=${3?:odir ?!}

  exe=$workdir/$odir/fuzz-$fuzzer
  if [[ ! -x $exe ]]; then
    echo "no exe found for $fuzzer"
    return 1
  fi

  # optional: dictionary for the fuzzer
  dict="$TOR/src/test/fuzz/dict/$fuzzer"
  [[ -e $dict ]] && dict="-x $dict" || dict=""

  nohup nice -n 1 /usr/bin/afl-fuzz -i $idir -o $workdir/$odir -m 9000 $dict -- $exe &>>$workdir/$odir/fuzz.log &
  pid=$!

  sudo $installdir/fuzz_helper.sh $odir $pid || echo "something failed with CGroups"
  echo " started $fuzzer pid=$pid in $workdir/$odir"
}


# resume stopped fuzzer(s)
function ResumeFuzzers()  {
  local count=${1:-0}

  test -z "${count//[0-9]}" || return 1

  local i=0
  for d in $(__listWorkDirs)
  do
    __isRunning $d && continue
    odir=$(basename $d)
    fuzzer=$(echo $odir | cut -f1 -d'_')
    idir="-"
    echo " resuming $odir ..."
    startIt $fuzzer $idir $odir
    echo

    ((i=i+1))
    [[ $count -gt 0 && $i -ge $count ]] && break
  done
}


# spin up new fuzzer(s)
function startFuzzer()  {

  test -z "${1//[0-9]}"
  if [[ $? -eq 0 ]]; then
    # integer given
    local count="$1"
    all=""
    for fuzzer in $(ls $TOR_FUZZ_CORPORA 2>/dev/null)
    do
      [[ -x $TOR/src/test/fuzz/fuzz-$fuzzer           ]] || continue
      [[ -z "$(ls $workdir/${fuzzer}_* 2>/dev/null)"  ]] || continue
      all="$all $fuzzer"
    done
    fuzzers=$(echo $all | xargs -n 1 | shuf -n $count)
  else
    # fuzzer name(s) given
    fuzzers="$1"
  fi

  for fuzzer in $fuzzers
  do
    idir=$TOR_FUZZ_CORPORA/$fuzzer
    if [[ ! -d $idir ]]; then
      echo " idir not found: $idir"
      return 1
    fi

    cid=$(cd $TOR; git describe 2>/dev/null | sed 's/.*\-g//g')
    odir=${fuzzer}_$(date +%Y%m%d-%H%M%S)_${cid}
    mkdir -p $workdir/$odir || return 2
    cp $TOR/src/test/fuzz/fuzz-${fuzzer} $workdir/$odir
    startIt $fuzzer $idir $odir
    echo
  done
}


# update software stack
#
function updateSources() {
  echo " update deps ..."

  cd $RECIDIVM
  git pull
  make || return 1

  cd $TOR_FUZZ_CORPORA
  git pull

  cd $TOR
  git pull | grep -q "Already up to date."
  if [[ $? -ne 0 ]]; then
    make distclean
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

# simple lock to avoid being run in parallel
#
lck=~/.lock
if [[ -s $lck ]]; then
  echo -n " found $lck,"
  ls -l $lck
  tail -v $lck
  kill -0 $(cat $lck) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo " valid, exiting ..."
    exit 1
  else
    echo " stalled, continuing ..."
  fi
fi
echo $$ > $lck

cd $(dirname $0)
installdir=$(pwd)

# sources
export RECIDIVM=~/recidivm
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora
export TOR=~/tor

# common
export CFLAGS="-O2 -pipe -march=native"

# afl-fuzz
export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
export AFL_NO_FORKSRV=0
export AFL_NO_AFFINITY=1
export AFL_SKIP_CPUFREQ=1
export AFL_SHUFFLE_QUEUE=1

# llvm_mode
export CC="/usr/bin/afl-clang-fast"
export CXX="${CC}++"

results=~/results          # persistent
plotdir=/tmp/AFLplusplus   # plots only

abortdir=$results/abort
archdir=$results/archive
donedir=$results/done
workdir=$results/work

for d in $plotdir $abortdir $archdir $donedir $workdir
do
  if [[ ! -d $d ]]; then
    mkdir -p $d || exit 1
  fi
done

while getopts afghr:s:u\? opt
do
  case $opt in
    a)  archiveOrDone || break
        ;;
    f)  lookForFindings || break
        ;;
    g)  gnuplot || break
        ;;
    h|\?)Help
        ;;
    r)  ResumeFuzzers "$OPTARG" || break
        ;;
    s)  startFuzzer "$OPTARG" || break
        ;;
    u)  updateSources || break
        ;;
  esac
done

rm $lck
