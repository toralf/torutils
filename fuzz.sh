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
# git clone https://git.torproject.org/fuzzing-corpora.git
# git clone https://git.torproject.org/tor.git
#
# (III) build fuzzers:
#
# fuzz.sh -u
#
# (IV) start one arbitrarily choosen fuzzer:
#
# fuzz.sh -s 1


function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-afgu] [-r <# of fuzzers to be resumed> ] [-s '<fuzzer name(s)>'|<# of new fuzzers>]"
  echo
}



function __listWorkDirs() {
  ls -t $workdir/*_20??????-??????_*/fuzz-* 2>/dev/null | xargs --no-run-if-empty -n 1 dirname | tac
}


function __getPid() {
  awk '/fuzzer_pid/ { print $3 }' $1/default/fuzzer_stats 2>/dev/null
}


# 0 = runnning
# 1 = stopped
function __isRunning()  {
  local pid=$(__getPid $1)
  if [[ -n "$pid" ]]; then
    if ! kill -0 $pid 2>/dev/null; then
      return 2
    fi
    return 0
  fi

  return 1
}


function archiveOrDone()  {
  for d in $(__listWorkDirs)
  do
    if __isRunning $d; then
      continue
    fi

    local logfile=$d/fuzz.log
    if ls $d/default/{crashes,hangs}/* 2>/dev/null; then
      echo
      echo " archive: $d"
      mv $d $archdir

    elif tail -n 10 $logfile | grep -m 1 "^\[-\] PROGRAM ABORT :"; then
      echo
      echo " aborted: $d"
      mv $d $abortdir

      # check the latest abort reason only
    elif tac $logfile | grep -m 1 "^+++ Testing aborted .* +++" | grep -q "programmatically"; then
      echo
      echo " done: $d"
      mv $d $donedir
    fi

    rm -rf $plotdir/${d##*/}
  done
}


function lookForFindings()  {
  for d in $(__listWorkDirs)
  do
    for i in crashes hangs
    do
      if ! ls $d/default/$i/* 2>/dev/null; then
        continue
      fi

      local tbz2=$(basename $d)-$i.tbz2
      # already reported ?
      if [[ -f $d/$tbz2 && $d/$tbz2 -ot $d/$i ]]; then
        continue
      fi

      (
        echo "verify $i it with 'cd $d; ./fuzz-* < ./default/$i/id*' before informing tor-security@lists.torproject.org"
        echo
        cd $d
        tar -cjpf $tbz2 ./default/$i 2>&1
        uuencode $tbz2 $(basename $tbz2)
      ) | mail -s "$(basename $0): found $i in $d/default" $mailto -a "" || true
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
    afl-plot $d/default $destdir &>/dev/null
  done
}


# spin up the given fuzzer
function startIt()  {
  local fuzzer=${1?:fuzzer ?!}
  local idir=${2?:idir ?!}
  local odir=${3?:odir ?!}

  local exe=$workdir/$odir/fuzz-$fuzzer
  if [[ ! -x $exe ]]; then
    echo "no exe found for $fuzzer"
    return 1
  fi

  # optional: dictionary for the fuzzer
  local dict="$TOR/src/test/fuzz/dict/$fuzzer"
  [[ -e $dict ]] && dict="-x $dict" || dict=""

  local tmpdir=/tmp/fuzz/fuzz-${fuzzer}
  [[ -d $tmpdir ]] || mkdir -p $tmpdir
  export AFL_TMPDIR=$tmpdir

  nohup nice -n 1 /usr/bin/afl-fuzz -i $idir -o $workdir/$odir $dict -- $exe &>>$workdir/$odir/fuzz.log &
  local pid=$!

  sudo $installdir/fuzz_helper.sh $odir $pid || echo "something failed with CGroups"
  echo " started $fuzzer pid=$pid in $workdir/$odir"
}


# resume fuzzer(s)
function ResumeFuzzers()  {
  local count=${1?:count ?!}

  local i=0
  for d in $(__listWorkDirs)
  do
    if __isRunning $d; then
      continue
    fi
    idir="-"
    odir=$(basename $d)
    fuzzer=$(echo $odir | cut -f1 -d'_')
    echo -n " resuming:"
    startIt $fuzzer $idir $odir
    ((i=i+1))
    if [[ $i -ge $count ]]; then
      break
    fi
  done
}


# spin up new fuzzer(s)
function startFuzzer()  {
  if test -z "${1//[0-9]}"; then
    # integer given
    local count="$1"
    local all=""
    local fuzzers=""
    for fuzzer in $(ls $FUZZING_CORPORA 2>/dev/null)
    do
      if [[ ! -x $TOR/src/test/fuzz/fuzz-$fuzzer ]]; then
        continue
      fi
      if [[ -n "$(ls $workdir/${fuzzer}_* 2>/dev/null)" ]]; then
        continue
      fi
      all="$all $fuzzer"
    done
    fuzzers=$(echo $all | xargs -n 1 | shuf -n $count)
  else
    # fuzzer name(s) given
    fuzzers="$1"
  fi

  for fuzzer in $fuzzers
  do
    local idir=$FUZZING_CORPORA/$fuzzer
    if [[ ! -d $idir ]]; then
      echo " idir not found: $idir"
      return 1
    fi

    local cid=$(cd $TOR; git describe 2>/dev/null | sed 's/.*\-g//g')
    local odir=${fuzzer}_$(date +%Y%m%d-%H%M%S)_${cid}
    mkdir -p $workdir/$odir
    cp $TOR/src/test/fuzz/fuzz-${fuzzer} $workdir/$odir
    startIt $fuzzer $idir $odir
    echo
  done
}


# update software stack
#
function updateSources() {
  echo " update deps ..."

  set -e

  cd $FUZZING_CORPORA
  git pull

  cd $TOR
  if ! git pull | grep -q "Already up to date."; then
    make distclean
  fi

  if [[ ! -x ./configure ]]; then
    rm -f Makefile
    echo " autogen ..."
    if ! ./autogen.sh 2>&1; then
      return 2
    fi
  fi

  if [[ ! -f Makefile ]]; then
    # use the configre options from the official Gentoo ebuild, but :
    #   - disable coverage, this has a huge slowdown effect
    #   - enable zstd-advanced-apis
    echo " configure ..."
    local gentoo_options="
        --prefix=/usr --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu --mandir=/usr/share/man --infodir=/usr/share/info --datadir=/usr/share --sysconfdir=/etc --localstatedir=/var/lib --disable-dependency-tracking --disable-silent-rules --docdir=/usr/share/doc/tor-0.4.3.5 --htmldir=/usr/share/doc/tor-0.4.3.5/html --libdir=/usr/lib64 --localstatedir=/var --enable-system-torrc --disable-android --disable-html-manual --disable-libfuzzer --enable-missing-doc-warnings --disable-module-dirauth --enable-pic --disable-rust --disable-restart-debugging --disable-zstd-advanced-apis --enable-asciidoc --enable-manpage --enable-lzma --enable-libscrypt --enable-seccomp --enable-module-relay --disable-systemd --enable-gcc-hardening --enable-linker-hardening --disable-unittests --disable-coverage --enable-zstd
    "
    local override="
        --enable-module-dirauth --enable-zstd-advanced-apis --enable-unittests --disable-coverage
    "
    if ! ./configure $gentoo_options $override; then
      return 3
    fi
  fi

  # https://trac.torproject.org/projects/tor/ticket/29520
  echo " make ..."
  if ! make micro-revision.i 2>&1; then
    return 4
  fi

  if ! make -j8 fuzzers 2>&1; then
    return 5
  fi
  echo
}


#######################################################################
#
# main
#
set -eu
export LANG=C.utf8

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
  if kill -0 $(cat $lck) 2>/dev/null; then
    echo " valid, exiting ..."
    exit 1
  else
    echo " stalled, continuing ..."
  fi
fi
echo $$ > $lck

cd $(dirname $0)
installdir=$(pwd)

# Tor sources
export FUZZING_CORPORA=~/fuzzing-corpora
export TOR=~/tor

export CFLAGS="-O2 -pipe -march=native"

export AFL_EXIT_WHEN_DONE=1
export AFL_HARDEN=1
# export AFL_NO_AFFINITY=1
# export AFL_NO_FORKSRV=1
export AFL_SKIP_CPUFREQ=1
# export AFL_SHUFFLE_QUEUE=1

export CC="/usr/bin/afl-cc"
export CXX="/usr/bin/afl-c++"

results=~/results          # persistent
plotdir=/tmp/AFLplusplus   # plotted graphs

abortdir=$results/abort
archdir=$results/archive
donedir=$results/done
workdir=$results/work

for d in $plotdir $abortdir $archdir $donedir $workdir
do
  [[ -d $d ]] || mkdir -p $d
done

while getopts afghr:s:u\? opt
do
  case $opt in
    a)    archiveOrDone || break            ;;
    f)    lookForFindings || break          ;;
    g)    gnuplot || break                  ;;
    h|\?) Help                              ;;
    r)    ResumeFuzzers "$OPTARG" || break  ;;
    s)    startFuzzer "$OPTARG" || break    ;;
    u)    updateSources || break            ;;
  esac
done

rm $lck
