[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks at the IP [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) ¹.
The goal is to target the (presumably) intention of the attacker to unveil onion services.

This DDoS solution uses [ipsets](https://ipset.netfilter.org) are used.
Its _timeout_ feature provides a long term memory to still block an ip where plain iptables rules would (no longer) fire.
Compare the counters for IPv4 of line [14](./doc/iptables-L.txt#L14) and [15](./doc/iptables-L.txt#L15)
and for IPv6 of line [16](./doc/ip6tables-L.txt#L16) and [17](./doc/ip6tables-L.txt#L17) respectively.

Metrics of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days
for [these](https://nusenu.github.io/OrNetStats/zwiebeltoralf.de.html) 2 relays.
A heavier attack was observed at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
And, a periodic drop down of the socket count metric, vanishing over time as seen at
[5th](./doc/network-metric-Dec-05th.svg) of Dec, was observed.

¹ Discussion started in ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636),
continued in ticket [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/).

### Quick start

Install the dependencies, eg. for Ubuntu 22.04:

```bash
sudo apt install iptables ipset jq
```

Then run:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

This replaces any current content of the iptables _filter_ table with the rule set described below.
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

#### Objectives

Neither touch established nor outbound connections. ¹
Filter only ips, no network blocking. ²

#### Details

Generic rules for local network, ICMP, ssh and user services (if defined) are applied.
Then these rules are applied (in this order) for a connection attempt to the local ORPort:

1. trust Tor authorities and snowflake
1. block ip for 1 day if the rate is > 6/min
1. allow if the ip is known to host 2 relays and the current connection count from there is below 2
1. allow not more than 2 connections ³
1. rate limit new connection attempts by 0.5/minute
1. accept the connection attempt

¹ An attacker capable to spoof ip addresses could easily force those ip address to be blocked at any time after the connection was established.

² An attacker could place 1 malicious ip within a /24 or /16 range and harms all of them at once otherwise.

³ The connection limit sounds rigid.
But how likely is it that more than 2 Tor proxies behind the same (NATed) ip address do connect to the same guard/entrynode at the same time?
Would that likelihood rule the sizing of a DDoS solution?

### Installation

The instructions belongs to the IPv4 variant.
They can be applied in a similar way for the IPv6 variant of the script.

If the parsing of the Tor config (line [186](ipv4-rules.sh#L186)) doesn't work for you then:

1. define the local running relay(s) space separated at the command line after the keyword `start`, eg.:

    ```bash
    sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
    ```

    (command line overrules environment)

1. -or- define them within the environment, eg.:

    ```bash
    sudo CONFIGURED_RELAYS="5.6.7.8:9001 1.2.3.4:443" ./ipv4-rules.sh start
    ```

    (`CONFIGURED_RELAYS6` for the IPv6 case).

Appreciated is

1. to open [here](https://github.com/toralf/torutils/issues) an issue about it

1. -or- to create a GitHub PR with the fix ;)

To allow inbound traffic to other local service(s), either:

1. define them in the environment space separated, eg.:

    ```bash
    ADD_LOCAL_SERVICES="2.718.281.828:459"
    ```

    (`ADD_LOCAL_SERVICES6` respectively)
1. -or- change the default filter policy for an incoming packet:

    ```bash
    DEFAULT_POLICY_INPUT="ACCEPT"
    ```

before you start the script.

To **append** the rules of this script onto the local _iptables_ rules (instead **overwrite** existing rules)
comment out the `clearAll` call (line [229](ipv4-rules.sh#L229)).
The script sets few _sysctl_ values (line [230](ipv4-rules.sh#L230)).
Preferred is however to set those configs under _/etc/sysctl.d/_ outsite of the script.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out the `addHetzner` call (line [232](ipv4-rules.sh#L232)).

### Helpers

Few scripts were made to fine tune the parameters of the rule set:

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to the ORPort than a given
limit ([example](./doc/ddos-inbound.sh.txt)).
[hash-stats.sh](./hash-stats.sh) plots the distribution of timeout values of an iptables hash
([example](./doc/hash-stats.sh.txt)).
[ipset-stats.sh](./ipset-stats.sh) plots distribution of timeout values of an ipset as well as occurrences
of ip addresses in subsequent ipset output files ([example](./doc/ipset-stats.sh.txt)).
The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

The SVG graphs are created by:

```bash
args="-n DEV,SOCK,SOCK6 --iface=enp8s0"   # set it to "-A" to display all collected metrics
svg=/tmp/graph.svg
TZ=UTC sadf -g -T /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args > $svg
h=$(tail -n 2 $svg | head -n 1 | cut -f5 -d' ')   # fix the SVG canvas size
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

The data shown in the [first chapter](#block-ddos) are collected by [sysstat]((http://sebastien.godard.pagesperso-orange.fr/)).
This crontab entry is used to sample 1 data point per minute:

```crontab
@reboot     /usr/lib/sa/sa1 --boot
* * * * *   /usr/lib/sa/sa1 1 1 -S XALL
```

## Query Tor via its API

### Relay summary

[info.py](./info.py) gives a summary of all connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051

 ORport 9051  0.4.8.0-alpha-dev   uptime: 02:58:04   flags: Fast, Guard, Running, Stable, V2Dir, Valid
+------------------------------+-------+-------+
| Type                         |  IPv4 |  IPv6 |
+------------------------------+-------+-------+
| Inbound to our OR from relay |  2304 |   885 |
| Inbound to our OR from other |  3188 |    68 |
| Inbound to our ControlPort   |       |     1 |
| Outbound to relay OR         |  2551 |   629 |
| Outbound to relay non-OR     |       |       |
| Outbound exit traffic        |       |       |
| Outbound unknown             |    16 |     4 |
+------------------------------+-------+-------+
| Total                        |  8059 |  1587 |
+------------------------------+-------+-------+
 relay OR connections  6369
 relay OR ips          5753
    3 inbound v4 with > 2 connections each
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
