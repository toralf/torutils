[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg).
Another blocked DDoS attack is seen [here](./doc/network-metric-July-3rd.jpg).
More example are [below](#ddos-examples).

This solution uses [ipsets](https://ipset.netfilter.org).
The _timeout_ property of an ipset provides the ability to block an ip for a much longer time
than a plain iptables hashlimit rule would do.
IMO this is shown in [this](./doc/iptables-L.txt) example by the difference of the SET and DROP counters
(line [14](./doc/iptables-L.txt#L14) and [15](./doc/iptables-L.txt#L15) for IPv4,
line [16](./doc/ip6tables-L.txt#L16) and [17](./doc/ip6tables-L.txt#L17) for IPv6).

¹ see ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and ticket [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/) tracker.

### Quick start

Install the dependencies, e.g. for Ubuntu 22.04:

```bash
sudo apt install iptables ipset jq
```

Make a backup of the current iptables _filter_ table before if wanted.
Then run:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

This replaces any current content of the iptables _filter_ table with the rule set described below.
Best is to (re-)start Tor afterwards.
If the script doesn't work out of the box then please proceed with the [Installation](#installation) section.

The live statistics can be watched by:

```bash
sudo watch -t ./ipv4-rules.sh
```

To stop DDoS prevention and clear the _filter_ table, run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule set

#### Objectives

- Neither touch established nor outbound connections.¹
- Filter only single ips, no network segments.²

¹ An attacker capable to spoof ip addresses could easily force blocking victim ip addresses.

² An attacker could place 1 malicious ip within a CIDR range to harm all other addresses in the same network block.

#### Details

Generic rules for local network, ICMP, ssh and local user services (if defined) are applied.
Then these rules are applied (in this order) for a connection attempt from an ip to the local ORPort:

1. trust ip of Tor authorities and snowflake
1. allow up to 8 connections from the same ip if the ip is known to host >1 relays
1. block ip for 1 day if the rate is > 6/min
1. drop if there are already 2 established connections from the same ip¹
1. rate limit new connection attempts at 0.5/minute
1. accept it

¹ This connection limit sounds rigid.
But how likely do more than the given number of Tor clients at the same ip address do connect to the same guard at the same time?

### Installation

The instructions belongs to the IPv4 variant.

Rule 3 depends on recent data of ip addresses serving more than one Tor relay.
To update that data run this in regular intervalls (best: via cron):

```bash
sudo ./ipv4-rules.sh update
```

If the parsing of the Tor config (line [170](ipv4-rules.sh#L170)) doesn't work for you then:

1. define the local running relay(s) at the command line after the keyword `start`, e.g.:

   ```bash
   sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
   ```

   (command line values overwrite environment values)

1. -or- define them within the environment, e.g.:

   ```bash
   sudo CONFIGURED_RELAYS="5.6.7.8:9001 1.2.3.4:443" ./ipv4-rules.sh start
   ```

   (`CONFIGURED_RELAYS6` for the IPv6 case).

I do appreciate an issue request [here](https://github.com/toralf/torutils/issues) -or- a GitHub PR with a fix ;)

To allow inbound traffic to other local service(s), do either:

1. define them in the environment (space separated), e.g.:

   ```bash
   ADD_LOCAL_SERVICES="27.18.281.828:555"
   ```

   (`ADD_LOCAL_SERVICES6` respectively)

1. -or- change the default filter policy for an incoming packet:

   ```bash
   DEFAULT_POLICY_INPUT="ACCEPT"
   ```

before you start the script.
To **append** the rules of this script onto the local _iptables_ rules (**overwrite** of existing rules is the default)
you've to comment out the call _clearRules()_ (line [221](ipv4-rules.sh#L221)).

The script sets few _sysctl_ values (line [144](ipv4-rules.sh#L144)).
As an alternative set them under _/etc/sysctl.d_.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out the call _addHetzner()_ (line [224](ipv4-rules.sh#L224)).

### Helpers

Few scripts helps to fine tune the parameters of the rule set.
[metrics.sh](./metrics.sh) exports data to Prometheus.
[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to the ORPort than a given
limit ([example](./doc/ddos-inbound.sh.txt)).
[hash-stats.sh](./hash-stats.sh) plots the distribution of timeout values of an iptables hash
([example](./doc/hash-stats.sh.txt)).
[ipset-stats.sh](./ipset-stats.sh) plots distribution of timeout values of an ipset as well as occurrences
of ip addresses in subsequent ipset output files ([example](./doc/ipset-stats.sh.txt)).
For plots the package [gnuplot](http://www.gnuplot.info/) is needed.
The SVG graphs are created by the sysstat command _sadf_, the canvas size is fixed for
an already [reported issue](https://github.com/sysstat/sysstat/issues/286):

```bash
args="-n DEV,SOCK,SOCK6 --iface=enp8s0"   # set it to "-A" to display all collected metrics
svg=/tmp/graph.svg
sadf -g -t /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args > $svg
h=$(tail -n 2 $svg | head -n 1 | cut -f 5 -d ' ')   # fix the SVG canvas size
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

The upload is made by [node_exporter](https://github.com/prometheus/node_exporter).

### DDoS examples

Metrics¹ of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days
for [these](https://nusenu.github.io/OrNetStats/zwiebeltoralf.de.html) 2 relays.
A more heavier attack was observed at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
A periodic drop down of the socket count metric, vanishing over time, appeared at
[5th](./doc/network-metric-Dec-05th.svg) of Dec.
Current attacks e.g. at the [7th](./doc/network-metric-Mar-7th.svg) of March are still handled well.

¹ Graphs are created by [sysstat](http://sebastien.godard.pagesperso-orange.fr/).
In the mean while I do use [this](./grafana-dashboard.json) Grafana dashboard and the scripts under [Helpers](#helpers).

## Query Tor via its API

### Relay summary

[info.py](./info.py) gives a summary of all connections, e.g.:

```console
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

### Watch Tor Exit connections

If your Tor relay is running as an _Exit_ then [ps.py](./ps.py) gives live statistics:

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

### Check expiration of Tor offline keys

[key-expires.py](./key-expires.py) helps to maintain
[Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/).
It returns the expiration time in seconds of the mid-term signing key, e.g.:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```

If the Tor metrics are enabled then this 1-liner works too (maybe replace `9052` with the actual metrics port):

```bash
date -d@$(curl -s localhost:9052/metrics | grep "^tor_relay_signing_cert_expiry_timestamp" | awk '{ print $2 }')
```

### Prerequisites

An open Tor control port is needed to query the Tor process via API.
Configure it in _torrc_, e.g.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The [Stem](https://stem.torproject.org/index.html) python library is needed too.
Install it either by your package manager -or- use the git sources, e.g.:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
