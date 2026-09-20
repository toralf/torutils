[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

This guide is about the _nftables_ variant.
For _iptables_ proceed with [README-iptables.md](./README-iptables.md).

## DDoS protection

Protect a linux system against DDoS attacks ¹ at [network level](https://thermalcircle.de/doku.php?id=blog:linux:nftables_packet_flow_netfilter_hooks_detail)
as seen in this example:

![image](./doc/dopped_ipv4_2024-03.jpg)

Another example is [this](./doc/network-metric-July-3rd.jpg).
It reminds me of university lectures on signal processing and detecting sonar echoes in received data.

¹ ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/).

### Idea

A remote system is considered malicious if its connection attempts to the local Tor instance over a short time interval exceed the expected threshold.
Block such systems for a long time interval.
Further considerations:

- never touch established connections
- avoid overblock

### Quick start

Install _nftables_, e.g. at Debian:

```bash
sudo apt install -y nftables
```

Download [nftables-ingress.conf](./nftables-ingress.conf).
It contains a complete ruleset for a Linux system running Tor.
Ignore its size.
For a common Tor installation replace `LOCAL_V4_ADDRESS`, `LOCAL_V6_ADDRESS` and `TOR_PORT` with your values.
Lint it:

```bash
nft -c -f <edited file>
```

Copy it onto /etc/nftables.conf (make a backup before).
Ensure that your kernel sysctl values fit, e.g.:

```bash
cat /etc/sysctl.d/21firewall.conf

net.core.somaxconn = 131072
net.ipv4.tcp_max_syn_backlog = 131072
net.ipv4.tcp_syncookies = 1
net.netfilter.nf_conntrack_buckets = 131072
net.netfilter.nf_conntrack_max = 131072
```

I do set few more values for my systems, e.g.
[here](https://github.com/toralf/tor-relays/blob/main/playbooks/roles/setup_common/tasks/system-config.yaml#L39).
Reload the firewall service:

```bash
service nftables reload
```

If your system works as expected - enjoy it.
If something went wrong then restore the backup.
Check [Configuration](#configuration) before please.

### The Rule Set

1. trust any connection attempt from a Tor authority node
2. block the source ¹ for 24 hours if the connection attempt rate exceeds 8/min ² within last 5 minutes - or -
3. block the source ¹ for 24 hours if the connection attempt rate exceeds 24/hour within last 2 hours ³
4. ignore the connection attempt if there are already 8 established connections
5. accept the connection attempt

The ruleset applies to each defined [OR address, OR port] pair.

¹ Per default the _source_ is a IPv4 address or a /64 IPv6 respectively.

² Values were discussed in [ticket 40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636#note_2844146).

³ No overblocking even if the _source_ and/or the local system are rebooted few times in a row

### Avoid abuse complaints / server blocking

For _iptables_ proceed with [README-iptables.md](./README-iptables.md#avoid-abuse-complaints--server-blocking).

Every then and when Tor relay operators do get an undesired abuse complaint from a hoster.
Details are in [this](https://gitlab.torproject.org/tpo/network-health/analysis/-/issues/105) ticket.
To avoid complaints:
Download [nftables-egress.conf](./nftables-egress.conf), check and load it

```bash
nft -c -f nftables-egress.conf && nft -o -f nftables-egress.conf
```

Persist it by appending it to your existing nftables config file.

### Configuration

If you run more than 1 Tor instance at the same system then add all [address, port] pairs
to the `tor_v4` and `tor_v6` set respectively.
For a Snowflake standalone proxy uncomment the Snowflake part (and remove the Tor part).
Configure additional local services under

```yaml
# ======== ADDITIONAL BEGIN ========
```

### Metrics

The script [metrics-firewall.sh](./metrics-firewall.sh) exports firewall metrics into a Prometheus readable file.
More details and few Grafana dashboards are in [dashboards](./dashboards/README.md).

### Few more DDoS examples

Graphs¹ of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days for 2 relays.
A heavy attack was observed at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
A periodic drop down of the socket count metric, vanishing over time, appeared at
[5th](./doc/network-metric-Dec-05th.svg) of Dec.
Current attacks e.g. at the [7th](./doc/network-metric-Mar-7th.svg) of March are still handled well.
Few more helper scripts were developed to analyze the attack vector.
Look [here](./misc/README.md) for details.

¹ using [sysstat](http://sebastien.godard.pagesperso-orange.fr/)

# Misc stuff

## Query Tor via its API

### Relay summary

[info.py](./tools/info.py) gives a summary of all Tor related TCP connections, e.g.:

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

If your Tor relay is an _Exit_ then [ps.py](./tools/ps.py) gives live statistics about those network connections:

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

### Tor circuit closings

[orstatus.py](./tools/orstatus.py) prints the _closing reason_ to stdout,
[orstatus-stats.sh](./tools/orstatus-stats.sh) prints/plots statistics ([see this example](./doc/orstatus-stats.sh.txt)) from that.

```bash
orstatus.py --ctrlport 9051 --address 127.0.0.1 >>/tmp/orstatus &
sleep 3600
orstatus-stats.sh /tmp/orstatus
```

### Prerequisites

An open Tor control port is needed to query the Tor process via API.
Configure it in /etc/tor/torrc, e.g.:

```console
ControlPort 127.0.0.1:9051
```

The python library [Stem](https://stem.torproject.org/index.html) is needed.
Clone and use it:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

## Check expiration of Tor offline keys

[key-expires.py](./tools/key-expires.py) helps to maintain
[Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/).
It returns the expiration time in seconds of the mid-term signing key.
A cronjob for that task could look like this:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/keys/ed25519_signing_cert)
days=$((seconds / 86400))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```

If Tor metrics are enabled then this 1-liner does a similar job (replace `9052` with your metrics port):

```bash
date -d@$(curl -s localhost:9052/metrics | grep "^tor_relay_signing_cert_expiry_timestamp" | awk '{ print $2 }')
```

## Search logs for pre-defined text patterns

The script [watch.sh](./tools/watch.sh) helps to constantly monitor host and Tor logs.
It sends findings via _mailx_.

```bash
log=/tmp/${0##*/}.log

# watch syslog
sudo ./watch.sh /var/log/messages ./watch-messages.txt

# watch Tor
sudo ./watch.sh /var/log/tor/notice.log ./watch-tor.txt -v
```

# Participation

Please file issues at [this](https://github.com/toralf/torutils/issues) tracker.

# More

I use [this](https://github.com/toralf/tor-relays/) project to maintain Tor relays, bridges, Snowflake standalone proxies.
Furthermore, I use it for compile-tests of upcoming Linux kernels.
