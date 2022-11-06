[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against inbound DDoS attacks at the IPv4/6 [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) respectively.

The goal is much more than traffic control:
The (presumably) intention of the attacker is targeted.
Therefore, in addition to network filtering a transformation of the (currently) sharp input signal
(==open few thousands TLS connections within second/s)
into a more smeared output response (which needs minutes to reach the maximum) is achieved.
This shall make it harder for an attacker to get reasonable results from a time correlation algorithm.

[This](./doc/network-metric.svg) metrics shows the response (last graph) to certain DDoS events at a day
as well as the cpu usage (the green line in that graph belongs to the Tor process, ignore the other colours in that graph).
And [here](./doc/network-metric-nextday.svg) are the graphs for the next day.
The metrics are created using the [sysstat](http://sebastien.godard.pagesperso-orange.fr/) package.

Origin discussion is in [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)
of the [Tor project](https://www.torproject.org/).

### Quick start

Run:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

to replace any current _filter_ table content with the rule set described below.
Best is to (re-)start Tor afterwards.
To clear the _filter_ table, run:

```bash
sudo ./ipv4-rules.sh stop
```

The live statistics can be watched by:

```bash
sudo watch -t ./ipv4-rules.sh
```

The output should look similar to the [IPv4](./doc/iptables-L.txt) and the [IPv6](./doc/ip6tables-L.txt) example respectively.

The package [iptables](https://www.netfilter.org/projects/iptables/) needs to be installed before.
### Rule set

Filter inbound connection attempts.
Neither touch established connections nor outbounds connections.

Details:

Generic rules for local network, ICMP, ssh and for user services (if defined) are applied.
Then these rules are applied (in this order) for a TCP connection attempt to the local ORPort:

1. trust Tor authorities and snowflake
1. block it for 30 min if the rate is > 5/min
1. limit rate to 1/min
1. ignore it if 4 connections are already established
1. accept it

These rules apply to single IPv4 ips and /80 IPv6 networks respectively.
For rule 2 an [ipset](https://ipset.netfilter.org) is used, the remaining rules are expressed
with the _hashlimit_ and _comnnlimit_ module of _iptables_.

### Configuration

The instructions belongs to the IPv4 variant.
They can be applied in a similar way for the IPv6 script.
If the parsing of _torrc_ doesn't work for you (line [119](ipv4-rules.sh#L119)) then:

1. define the relay(s) space separated in this environment variable before applying the rule set, eg.:

    ```bash
    export CONFIGURED_RELAYS="3.14.159.26:535"
    export CONFIGURED_RELAYS6="[cafe::dead:beef]:4711"
    ```

1. -or- create a pull requests to fix the code ;)

Same happens for additional local network services:

1. define them space separated in this environment variable before applying the rule set, eg.:

    ```bash
    export ADD_LOCAL_SERVICES="2.718.281.828:459"
    export ADD_LOCAL_SERVICES6="[edda:fade:affe:baff:eff:eff]:12345"
    ```

1. -or- append your iptables rules to the _filter_ table
1. -or- open the iptables chain _INPUT_ in line [6](ipv4-rules.sh#L6):

    ```bash
    iptables -P INPUT ACCEPT
    ```

    I won't recommended that however.

If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't needed, then

1. remove the _addHetzner()_ code (line [87ff](ipv4-rules.sh#L87)) and its call in line [147](ipv4-rules.sh#L147)
1. -or- just ignore it

If you run a previous version of this script then probably you need to delete the old ipset/s before:

```bash
ipset list -t | grep "^Name"
# ipset destroy <choose one from the list above>
```

### Fine tuning

These scripts helped to fine tune certain rule set parameters.
[Feedback](https://github.com/toralf/torutils/issues) about the parameters is highly appreciated.

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more connections from or to the ORPort than a given limit (4 per default).
[orstatus.py](./orstatus.py) logs the reason of Tor circuit closing events.
[orstatus-stats.sh](./orstatus-stats.sh) prints and/or plots statistics like
[this](./doc/orstatus-stats.sh.txt) from that output.
[hash-stats.sh](./hash-stats.sh) plots the timeout values of the entries in an iptables hash
([example](./doc/hash-stats.sh.txt)),
[ipset-stats.sh](./ipset-stats.sh) does the same for the content of an ipset
([example](./doc/ipset-stats.sh.txt)).

The package [gnuplot](http://www.gnuplot.info/) is needed to plot the graphs.
For sysstat use this crontab entry:

```bash
# crontab root

# sysstat
@reboot     /usr/lib/sa/sa1 --boot
* * * * *   /usr/lib/sa/sa1 1 1 -S XALL
```

and create the graphs by (adapt _args_ for your system):

```bash
args="-u -n DEV,SOCK --iface=enp8s0"
svg=/tmp/graph.svg
TZ=UTC sadf -g -t /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args > $svg
h=$(tail -n 2 $svg | head -n 1 | cut -f5 -d' ')  # to fix the SVG code
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

## Query Tor via its API

[info.py](./info.py) gives a summary of all connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gives here:

```console
 ORport 9051
 0.4.8.0-alpha-dev   uptime: 01:50:23   flags: Fast, Guard, Running, Stable, V2Dir, Valid

+------------------------------+-------+-------+
| Type                         |  IPv4 |  IPv6 |
+------------------------------+-------+-------+
| Inbound to our OR from relay |  2654 |   884 |
| Inbound to our OR from other |  5583 |    77 |
| Inbound to our ControlPort   |     1 |     2 |
| Outbound to relay OR         |  2209 |   576 |
| Outbound to relay non-OR     |       |       |
| Outbound exit traffic        |       |       |
| Outbound unknown             |     6 |       |
+------------------------------+-------+-------+
| Total                        | 10453 |  1539 |
+------------------------------+-------+-------+
```

For a monitoring of _exit_ connections use [ps.py](./ps.py):

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

An open Tor control port is needed to query the Tor process via API.
Configure it in _torrc_, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The [Stem](https://stem.torproject.org/index.html) python library is mandatory.
The latest version can be derived at:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

## Tor offline keys

If you do use [Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/)
then [key-expires.py](./key-expires.py) helps you to not miss the key rotation timeline.
It returns the seconds before the mid-term signing key expires, eg:

```bash
seconds=$(/opt/torutils/key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```
