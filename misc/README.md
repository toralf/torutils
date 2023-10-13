[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# misc

## deprecated tools

[ddos-inbound.sh](../ddos-inbound.sh) lists ips having more inbound connections to the ORPort than a given
limit ([example](../doc/ddos-inbound.sh.txt)).
[hash-stats.sh](../hash-stats.sh) plots the distribution of timeout values of an iptables hash
([example](../doc/hash-stats.sh.txt)).
[ipset-stats.sh](../ipset-stats.sh) plots distribution of timeout values of an ipset as well as occurrences
of ip addresses in subsequent ipset output files ([example](../doc/ipset-stats.sh.txt)).
For plots the package [gnuplot](http://www.gnuplot.info/) is needed.
The SVG graphs are created by the sysstat command _sadf_, the canvas size is fixed for
an already [reported issue](https://github.com/sysstat/sysstat/issues/286) in this way:

```bash
args="-n DEV,SOCK,SOCK6 --iface=enp8s0" # set it to "-A" to display all collected metrics
svg=/tmp/graph.svg
sadf -g -t /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args >$svg
h=$(tail -n 2 $svg | head -n 1 | cut -f 5 -d ' ') # fix the SVG canvas size
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

## 1-liners

A quick check for blocked relays is made by

```bash
for v in "" 6; do
  for i in $(ipset list -t | awk '/^Name: tor-ddos'$v'-/ { print $2 }'); do
    ipset list $i | sed -e '1,8d'
  done |
  grep -f /var/tmp/relays$v | awk '{ print $1 }' | sort | uniq -c | sort -bn
  echo
done
```
