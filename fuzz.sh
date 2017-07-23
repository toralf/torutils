#!/bin/bash
#
#set -x

# wrapper of common commands to fuzz test of Tor
# see https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md

mailto="torproject@zwiebeltoralf.de"

# preparation:
#
# echo "sys-devel/llvm clang" >> /etc/portage/package.use/llvm
# emerge --update sys-devel/clang
#
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
# git clone https://git.torproject.org/chutney.git
#
# <install recidivm>
#
# $ for i  in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm-0.1.1/recidivm -v $i 2>&1 | tail -n 1) $i ;  done | sort
# 40880663 ./tor/src/test/fuzz/fuzz-iptsv2
# 40880757 ./tor/src/test/fuzz/fuzz-consensus
# 40880890 ./tor/src/test/fuzz/fuzz-extrainfo
# 40885159 ./tor/src/test/fuzz/fuzz-hsdescv2
# 40885224 ./tor/src/test/fuzz/fuzz-http
# 40888156 ./tor/src/test/fuzz/fuzz-descriptor
# 40897371 ./tor/src/test/fuzz/fuzz-microdesc
# 40955570 ./tor/src/test/fuzz/fuzz-vrs


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
  cd $CHUTNEY_PATH || return 1
  git pull -q

  cd $TOR_FUZZ_CORPORA || return 1
  git pull -q

  cd $TOR_DIR || return 1
  before=$(git describe)
  git pull -q
  after=$(git describe)

  if [[ "$1" = "force" ||  ! -f ./configure ]]; then
    ./autogen.sh || return $?
  fi

  if [[ "$1" = "force" || "$before" != "$after" || ! -f Makefile ]]; then
    make distclean
    CC="afl-clang" ./configure --disable-memory-sentinels --enable-expensive-hardening || return $?
    make -j $N clean
  fi

  make -j $N fuzzers
  return $?
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

    timestamp=$( date +%Y%m%d-%H%M%S )

    odir="./work/${timestamp}_${commit}_${f}"
    mkdir -p $odir || continue

    nohup nice afl-fuzz -i ${TOR_FUZZ_CORPORA}/$f -o $odir -m 50000000 -- $exe &>$odir/log &
    # needed for a unique output dir if the same fuzzer
    # runs more than once at the same time
    sleep 1
  done

  pgrep "afl-fuzz" &>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "didn't found any running fuzzers ?!"
  fi
}


# check for findings and archive them
#
function archive()  {
  if [[ ! -d ~/archive ]]; then
    mkdir ~/archive
  fi

  cd ~/work || return 1
  ls -1d 201?????-??????_?????????_* 2> /dev/null |\
  while read d
  do
    for issue in crashes
    do
      out=$(mktemp /tmp/${issue}_XXXXXX)
      ls -l $d/$issue/* 1> $out 2> /dev/null  # "/*" forces an error and an empty stdout

      if [[ -s $out ]]; then
        a=~/archive/${issue}_$d.tbz2
        tar -cjpf $a $d &>> $out
        if [[ "$issue" = "crashes" ]]; then
          (cat $out; uuencode $a $(basename $a)) | timeout 120 mail -s "fuzz $issue in $d" $mailto
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
  echo "found lock file"
  exit 1
fi

touch ~/.lock

export AFL_HARDEN=1
export CHUTNEY_PATH=~/chutney/
export TOR_DIR=~/tor/
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora/

export AFL_SKIP_CPUFREQ=1

log=$(mktemp /tmp/fuzzXXXXXX)
while getopts af:hkn:suU opt
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
    u|U)
        kill_fuzzers
        update_tor $( [[ "$opt" = "U" ]] && echo "force" ) &> $log
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
