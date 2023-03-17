#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# use node_exporter's "textfile" feature to pump metrics into Prometheus


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin


ne_dir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux

if [[ ! -d $ne_dir ]]; then
  echo -e " exporter directory '$ne_dir' does not exist" >&2
  exit 1
fi


tmpfile=$(mktemp /tmp/$(basename $0).XXXXXX)

# iptables stats of "filter" table
var="torutils_packets"
echo -e "# HELP $var Total number of packets\n# TYPE $var gauge" >> $tmpfile
for v in "" 6
do
  if [[ -z $v ]]; then
    pars="pkts bytes target prot opt in out source destination misc"
  else
    pars="pkts bytes target prot     in out source destination misc"
  fi

  for table in filter
  do
    ip${v}tables -nvxL -t $table |
    grep 'DROP' |
    grep -v -e "^Chain" -e "^  *pkts" -e "^$" |
    while read -r $pars
    do
      dpt=$(grep -Eo "(dpt:[0-9]+)" <<< "$misc" | cut -f2 -d':')
      echo "$var{ipver=\"${v:-4}\",table=\"$table\",target=\"$target\",prot=\"$prot\",dpt=\"$dpt\",misc=\"$misc\"} $pkts"
    done >> $tmpfile
  done
done

# ipset stats
var="torutils_ipsets"
echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge" >> $tmpfile
for v in "" 6
do
  ipset list -t | grep -e "^N" | xargs -n 6 | awk '/tor-ddos'$v'-/ { print $2, $6 }' |
  while read -r name count
  do
    orport=$(cut -f3 -d'-' <<< $name)
    echo "$var{ipver=\"${v:-4}\",orport=\"$orport\"} $count" >> $tmpfile
  done
done

# iptables module hashlimit
var="torutils_hashlimit"
echo -e "# HELP $var Total number of ip addresses\n# TYPE $var gauge" >> $tmpfile
for v in "" 6
do
  wc -l /proc/net/ip${v}t_hashlimit/*ddos* |
  grep -F -e '-ddos-' |
  while read -r count name
  do
    orport=$(cut -f3 -d'-' <<< $name)
    echo "$var{ipver=\"${v:-4}\",orport=\"$orport\"} $count" >> $tmpfile
  done
done

mv $tmpfile $ne_dir/torutils.prom
chmod a+r  $ne_dir/torutils.prom
