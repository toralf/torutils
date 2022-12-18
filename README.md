[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg).

The goal is more than traffic shaping:
The (presumably) intention of the attacker to unveil onion service/s is targeted.
Therefore, in addition to network filtering, the usually rectangular input signal of the DDoS²
is achieved to be transformed into a more smeared output response³.
This should make it harder for an attacker to gather information using time correlation techniques.

Therefore [ipsets](https://ipset.netfilter.org) are used.
Its _timeout_ feature provides the long term memory for the propsed solution.
Given that, an ip will still be blocked when a plain iptables rule had already stopped to fire.
This is eg. seen in the counters of line 14 and 15 of the [IPv4](./doc/iptables-L.txt#L14)
and line 16 and 17 of the [IPv6](./doc/ip6tables-L.txt#L16) example respectively.

Metrics of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days.
A more heavier attack happened at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
And 3 weeks later a periodic drop down of the socket count metric, vanishing over time as seen at
[5th](./doc/network-metric-Dec-05th.svg) of Dec, was observed.

All metrics are got from [these](https://metrics.torproject.org/rs.html#search/65.21.94.13) 2 relays.

¹Discussion was started in [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636) and
continued in [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)
of the [Tor project](https://www.torproject.org/).

²Thousands of new TLS connections are opened within second/s, stayed for about hours, then closed suddenly.

³Much longer ramp-up time before maximum is reached.

### Quick start

Install the dependencies, eg. for Ubuntu 22.04, this is required:

```bash
sudo apt install iptables ipset jq
```

Run:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

This **replaces** any current content of the iptables _filter_ table with the rule set described below.
Make a backup of the current tables before if needed.
Best is to (re-)start Tor afterwards.
The live statistics can be watched by:

```bash
sudo watch -t ./ipv4-rules.sh
```

To stop DDoS prevention and clear the _filter_ table, run:

```bash
sudo ./ipv4-rules.sh stop
```

If the script doesn't work out of the box then please proceed with the [Installation](#installation) section.

### Rule set

Objectives:

Neither touch established nor outbound connections.
Filter only ips, no network blocking.

Details:

Generic rules for local network, ICMP, ssh and user services (if defined) are applied.
Then these 5 rules are applied (in this order) for an TCP connection attempt to the local ORPort:

1. trust Tor authorities and snowflake
1. block it for 1 day if the rate is > 6/min
1. defer new connection attempts by a rate limit of 0.5/minute
1. allow not more than 2 connections
1. accept it

This usually allows an ip to connect to the ORPort with its 1st SYN packet.
If the rate exceeds a given limit (rule 2) then any further connection attempt is blocked for a given time.
Otherwise subsquently (rule 3) few more connections are allowed up to a given maximum (rule 4).

The limit _N_ of rule 4 is always a trade off of the likelihood of blocking
_x-N_ Tor clients (_x_ > _N_) behind the same router connecting to the same Guard at the same time
and the _N_ possible TLS connections for a DDoS attacker.

### Installation

The instructions belongs to the IPv4 variant.
They can be applied in a similar way for the IPv6 script.

If the parsing of the Tor config (line [158](ipv4-rules.sh#L158)) doesn't work for you then:

1. define the relay(s) space separated at the command line after the keyword `start`, eg.:

    ```bash
    sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
    ```

1. -or- define them within the environment, eg.:

    ```bash
    export CONFIGURED_RELAYS="3.14.159.26:535 1.41.42.13:562"
    export CONFIGURED_RELAYS6="[cafe::dead:beef]:4711"
    ```

    before you start the script

1. -or- open an [issue](https://github.com/toralf/torutils/issues) for that

1. -or- create a GitHub PR with a fix ;)

To allow inbound traffic to additional local service(s) (the default input policy is `DROP`),
then:

1. define all of them space separated, eg.:

    ```bash
    export ADD_LOCAL_SERVICES="2.718.281.828:459"
    export ADD_LOCAL_SERVICES6="[edda:fade:baff:192::/112]:80"
    ```

1. -or- change the default filter policy for incoming packets:

    ```bash
    export DEFAULT_POLICY_INPUT="ACCEPT"
    ```

    (I wouldn't recommended the later.)

before you start the script.

If you want to **append** the rules of this script onto your rules (instead clearing all existing rules by this script)
then comment out the `clearAll` call (line [197](ipv4-rules.sh#L197)).

If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then either ignore that rule or comment out the `addHetzner` call (line [203](ipv4-rules.sh#L203)).


### Helpers

Few scripts were made to fine tune the parameters of the rule set:

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to the ORPort than a given limit.
[hash-stats.sh](./hash-stats.sh) plots the distribution of timeout values of an iptables hash ([example](./doc/hash-stats.sh.txt)).
[ipset-stats.sh](./ipset-stats.sh) plots distribution of timeout values of an ipset as well as occurrences of ip addresses in subsequent ipset output files ([example](./doc/ipset-stats.sh.txt)).
The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

The data shown in the [first chapter](#block-ddos) are collected by [sysstat]((http://sebastien.godard.pagesperso-orange.fr/)).
This crontab entry is used to sample 1 data point per minute:

```crontab
@reboot     /usr/lib/sa/sa1 --boot
* * * * *   /usr/lib/sa/sa1 1 1 -S XALL
```

The SVG graphs are created by:

```bash
args="-n DEV,SOCK,SOCK6 --iface=enp8s0"   # set it to "-A" to display all collected metrics
svg=/tmp/graph.svg
TZ=UTC sadf -g -T /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args > $svg
h=$(tail -n 2 $svg | head -n 1 | cut -f5 -d' ')   # fix the SVG canvas size
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

## Query Tor via its API

### Relay summary

[info.py](./info.py) gives a summary of all connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gives something like:

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

### Tor exit connections

[ps.py](./ps.py) gives live statistics:

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

### Tor circuit closings

[orstatus.py](./orstatus.py) prints the reason to stdout.
[orstatus-stats.sh](./orstatus-stats.sh) prints/plots statistics ([example](./doc/orstatus-stats.sh.txt)) from that.

```bash
orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus &
sleep 3600
orstatus-stats.sh /tmp/orstatus
```

### Tor offline keys

[key-expires.py](./key-expires.py) returns the time in seconds before the Tor mid-term signing key expires, eg:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```

This is helpfful if you use [Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/).

### Prerequisites

An open Tor control port is needed for all of the scripts above to query the Tor process via API.
Configure it in _torrc_, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The [Stem](https://stem.torproject.org/index.html) python library is needed too.
Install it by your package manager -or- use the Git version, eg.:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
