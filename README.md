[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP network layer ([graphic](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg)).

The solution uses [ipsets](https://ipset.netfilter.org).
Its _timeout_ property provides the ability to block an ip for a much longer time
than a plain iptables hashlimit rule would do.
[This](./doc/network-metric-July-3rd.jpg) example ([here](#ddos-examples) are more) might illustrate that.

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
Make a backup of the current _filter_ table before if needed.

### Rule set

#### Objectives

- Neither touch established nor outbound connections.¹
- Filter only ips, no network blocking.²

¹ An attacker capable to spoof ip addresses could easily force to block ip addresses with an already established connection.

² An attacker could place 1 malicious ip within e.g. a /24 range to harm all other addresses in that segment.

#### Details

Generic rules for local network, ICMP, ssh and user services (if defined) are applied.
Then these rules are applied (in this order) for a connection attempt from an ip to the local ORPort:

1. trust ip of Tor authorities and snowflake
1. allow up to 4 connections from the same ip if the ip is known to host up to 4 relays
1. block ip for 1 day if the rate is > 6/min
1. drop if there are already 2 established connections from the same ip¹
1. rate limit new connection attempts at 0.5/minute
1. accept it

¹ This connection limit sounds rigid.
But how likely do more than the given number of Tor clients at the same ip address do connect to the same guard at the same time?

### Installation

The instructions belongs to the IPv4 variant.
They can be applied in a similar way for the IPv6 variant of the script.

Rule 3 depends on recent data of ip addresses serving more than one Tor relay.
Therefore run this in regular intervalls (eg. via cron):

```bash
sudo ./ipv4-rules.sh update
```

If the parsing of the Tor config (line [168](ipv4-rules.sh#L168)) doesn't work for you then:

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

In addition I do appreciate

1. an issue request [here](https://github.com/toralf/torutils/issues)
1. -or- a GitHub PR with a fix ;)

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
you've to comment out the call _clearRules()_ (line [219](ipv4-rules.sh#L219)).
The script sets few _sysctl_ values (line [142](ipv4-rules.sh#L142)).
Those can be set permanently under _/etc/sysctl.d/_ outsite of this script.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out the call _addHetzner()_ (line [222](ipv4-rules.sh#L222)).

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

These crontab entries are used to collect/create metrics:

```crontab
# sysstat
@reboot     /usr/lib/sa/sa1 --boot
* * * * *   /usr/lib/sa/sa1 1 1 -S XALL

# prometheus
* * * * *   for i in {0..3}; do /opt/torutils/metrics.sh &>/dev/null; sleep 15; done
```

The upload is made by [node_exporter](https://github.com/prometheus/node_exporter).
To scrape metrics of Tor relays I configured Prometheus in this way:

```yaml
   - job_name: "<node_exporter hostname>"
    static_configs:
      - targets: ["localhost:9100"]

   - job_name: "Tor"
    static_configs:
      - targets: ["localhost:19052"]
        labels:
          orport: '443'
      - targets: ["localhost:29052"]
        labels:
          orport: '9001'
...
```

The label _orport_ can be any arbitrary string - I used the value itself.

### DDoS examples

The counter values of line [14](./doc/iptables-L.txt#L14) and [15](./doc/iptables-L.txt#L15) for IPv4
and line [16](./doc/ip6tables-L.txt#L16) and [17](./doc/ip6tables-L.txt#L17) for IPv6 respectively are examples.

Metrics² of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days
for [these](https://nusenu.github.io/OrNetStats/zwiebeltoralf.de.html) 2 relays.
A heavier attack was observed at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
A periodic drop down of the socket count metric, vanishing over time appeared at
[5th](./doc/network-metric-Dec-05th.svg) of Dec.
Current attacks e.g. at the [7th](./doc/network-metric-Mar-7th.svg) of March are still handled well.

¹ Discussion is e.g. in ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
of the [Tor project tracker](https://www.torproject.org/) and was
continued in ticket [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093).

² Graphs are created by [sysstat](http://sebastien.godard.pagesperso-orange.fr/).
Beside that I do use [this](./grafana-dashboard.json) Grafana dashboard and the scripts under [Helpers](#helpers).

## Query Tor via its API

### Relay summary

[info.py](./info.py) gives a summary of all connections, eg.:

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

[key-expires.py](./key-expires.py) helps to maintain
[Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/).
It returns the expiration time in seconds of the mid-term signing key, eg:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```

With Tor metrics enabled get the expiration date in a human readable way by:

```bash
date -d@$(curl -s localhost:9052/metrics | grep "^tor_relay_signing_cert_expiry_timestamp" | awk '{ print $2 }')
```

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
