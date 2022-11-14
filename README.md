[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks at the IPv4/v6 [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) respectively.

The goal is more than traffic shaping:
The (presumably) intention of the attacker to unveil onion service/s is targeted.
Therefore, in addition to network filtering, the usually rectangular input signal [*]
is transformed into a smeared output response [**].
This makes it harder for an attacker to gather information using time correlation techniques,
at least it makes the DDoS more expensive.

To achieve this goal an [ipset](https://ipset.netfilter.org) is used.
Its _timeout_ feature adds the needed "memory" for the whole solution to continue to block an as malicous considered ip
for a much longer time than an single iptables rule usually would do.

Metrics of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days.
And a much more heavier attack happened at [12th](./doc/network-metric-Nov-12th.svg) of Nov.

Discussion was started in [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636) and
continued in [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)
of the [Tor project](https://www.torproject.org/).

[*] thousands of new TLS connections are opened within second/s and stayed for a longer time, then closed altogether
[**] much longer time is needed before the maximum is reached -and/or- only 1 connection per ip is created

### Quick start

Run:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

to replace any current content of the _filter_ table with the rule set described below.
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
The package [iptables](https://www.netfilter.org/projects/iptables/) needs to be installed before,
the package [jq](https://stedolan.github.io/jq/) is adviced.
If the script doesn't work out of the box for you then please have a look at the [Installation](#installation) section.

### Rule set

Basics:

Filter inbound connection attempts.
Neither touch established connections nor outbounds connections.
Filter single ips, not networks.

Details:

Generic rules for local network, ICMP, ssh and user services (if defined) are applied.
Then these 5 rules are applied (in this order) for every TCP connection attempt to the local ORPort(s):

1. trust Tor authorities and snowflake
1. block it for 30 min if the rate is > 5/min
1. limit rate to 1/min
1. ignore it if 4 connections are already established
1. accept it

This usually allows an ip to create a connection with its 1st SYN packet.
Depending on the rate of inbound SYNs up to 4 connections, minute by minute, are allowed (rule 3+4).
But if the rate exceeds the limit (rule 2) then any further connection attempt is blocked for the next 30 min
even if the rate drops down below the limit within the timeframe.
Rules 1 and 5 are self-explained.

There's an ongoing discussion about SYN flood protection.
My answer is in `/etc/sysctl.d/local.conf`:

```console
net.ipv4.tcp_syncookies = 1
net.netfilter.nf_conntrack_buckets = 2097152
net.netfilter.nf_conntrack_max = 2097152
```

plus 1M size for ipsets and hashes.

### Installation

The instructions belongs to the IPv4 variant.
They can be applied in a similar way for the IPv6 script.

If the parsing of the Tor config (line [118](ipv4-rules.sh#L118)) doesn't work for you then:

1. define the relay(s) space separated before starting the script, eg.:

    ```bash
    export CONFIGURED_RELAYS="3.14.159.26:535"
    export CONFIGURED_RELAYS6="[cafe::dead:beef]:4711"
    ```

1. -or- create a pull requests to fix the code ;)

Same happens for ports of additional local network services:

1. define them space separated, eg.:

    ```bash
    export ADD_LOCAL_SERVICES="2.718.281.828:459"
    export ADD_LOCAL_SERVICES6="[edda:fade:affe:baff:eff:eff]:12345"
    ```

1. -or- run your own iptables rules
1. -or- change the default policy of the iptables chain _INPUT_ in line [6](ipv4-rules.sh#L6):

    ```bash
    iptables -P INPUT ACCEPT
    ```

    (I wouldn't recommended that)

If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't needed, then

1. remove the _addHetzner()_ code (line [88ff](ipv4-rules.sh#L88)) and its call in line [153](ipv4-rules.sh#L153)
1. -or- just ignore it

If you run an older version of the script then sometimes you need to delete the (old) ipset before.

### Fine tuning

Few scripts are used to fine tune parameters.

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to the ORPort than a given limit (4 per default).
[orstatus.py](./orstatus.py) logs the reason of every Tor circuit closing event.
[orstatus-stats.sh](./orstatus-stats.sh) prints/plots statistics ([example](./doc/orstatus-stats.sh.txt)) from that output.
[hash-stats.sh](./hash-stats.sh) plots the distribution of timeout values of an iptables hash ([example](./doc/hash-stats.sh.txt)).
[ipset-stats.sh](./ipset-stats.sh) plots data got from ipset(s) ([example](./doc/ipset-stats.sh.txt)).

The package [gnuplot](http://www.gnuplot.info/) is needed to plot the graphs.
To create [sysstat](http://sebastien.godard.pagesperso-orange.fr/) metrics this crontab entry for user `root` is used to gather the data:

```console
@reboot     /usr/lib/sa/sa1 --boot
* * * * *   /usr/lib/sa/sa1 1 1 -S XALL
```

The graphs are created by:

```bash
args="-u -n DEV,SOCK,SOCK6 --iface=enp8s0" # use -A to display all metrics
svg=/tmp/graph.svg
TZ=UTC sadf -g -t /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args > $svg
h=$(tail -n 2 $svg | head -n 1 | cut -f5 -d' ')  # fix the SVG canvas size
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

### Outlook

Currently I do play with a job, running once in a minute,
which resets the timeout value a fraction of arbitrarily chosen ip addresses of the block list:

```bash
for p in 443 9001
do
  /opt/torutils/ipset-stats.sh -d tor-ddos-$p |
  awk '{ if (rand() < 0.01) { print $1 } }' |
  xargs -r -n 1 -P 20 /usr/sbin/ipset add -exist tor-ddos-$p
done
```

The goal is to more smear the output response.

## Query Tor via its API

[info.py](./info.py) gives a summary of all connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gave here:

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
It returns the time in seconds before the Tor mid-term signing key expires, eg:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```
