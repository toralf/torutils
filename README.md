[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) layer, as seen in this metrics:

![image](./doc/dopped_ipv4_2024-03.jpg)

An older example is [here](./doc/network-metric-July-3rd.jpg).

¹ see ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/).

### Quick start

Install _jq_, _ipset_ and _iptables_, e.g. for Ubuntu 22.04

```bash
sudo apt update
sudo apt install -y jq ipset iptables
```

download the script

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
```

make a backup of the current iptables _filter_ table:

```bash
sudo /usr/sbin/iptables-save > ./rules.v4
sudo /usr/sbin/ip6tables-save > ./rules.v6
```

and run a quick test

```bash
sudo ./ipv4-rules.sh test
```

Best is to stop the Tor service(s) now.
Flush the connection tracking table

```bash
sudo /usr/sbin/conntrack -F
```

and (re-)start the Tor service.
Check that your ssh login and other services are still working.
Watch the iptables live statistics by:

```bash
sudo watch -t ./ipv4-rules.sh
```

If something failed then restore the previous state:

```bash
sudo ./ipv4-rules.sh stop
sudo /usr/sbin/iptables-restore < ./rules.v4
sudo /usr/sbin/ip6tables-restore < ./rules.v6
```

Otherwise run the script with the parameter `start` instead of `test`.

```bash
sudo ./ipv4-rules.sh start
```

and create cron jobs (via `crontab -e`) like these:

```cron
# DDoS prevention
@reboot /root/ipv4-rules.sh start; /root/ipv6-rules.sh start

# keep ips during reboot
@hourly /root/ipv4-rules.sh save; /root/ipv6-rules.sh save

# update Tor authorities
@daily  /root/ipv4-rules.sh update; /root/ipv6-rules.sh update
```

Ensure, that the package _iptables-persistent_ is either not installed or disabled.

That's all.

More hints are in the [Installation](#installation) section.
I do appreciate [issue](https://github.com/toralf/torutils/issues) reports
and GitHub [PR](https://github.com/toralf/torutils/pulls).

### Rule set

#### Objectives

- never touch established connections
- try to not overblock

#### Details

Generic filter rules for the local network, ICMP, ssh, DHCP and additional services are created.
Then the following rules are applied:

1. trust connection attempt to any port from trusted Tor authorities/Snowflake servers
2. block the source¹ for 24 hours if the connection attempt rate to the ORPort exceeds > 9/min² within last 2 minutes
3. ignore the connection attempt if there are already 9 established connections to the ORPort
4. accept the connection attempt to the ORPort

¹ for IPv4 the "source" is a regular ip, for IPv6 the corresponding /80 CIDR block

² the value is derived from ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636#note_2844146)

Basically just these rules were be implemented, for ipv4 [here](./ipv4-rules.sh#L56),
the rest of the script deals with all the stuff around that.

### Installation

If the parsing of the Tor and/or of the SSH config fails then:

1. define the local running relay/s explicitly at the command line after the keyword `start`, e.g.:

   ```bash
   sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
   ```

1. -or- define them as environment variables, e.g.:

   ```bash
   sudo CONFIGURED_RELAYS="5.6.7.8:9001 1.2.3.4:443" ./ipv4-rules.sh start
   ```

   (`CONFIGURED_RELAYS6` for IPv6).

A command line argument takes precedence over its environment variable.
The same syntax is sued to allow inbound traffic to additional <address:port> destinations, e.g.:

```bash
export ADD_LOCAL_SERVICES="2.71.82.81:828 3.141.59.26:53"
```

(`ADD_LOCAL_SERVICES6` appropriately) before running the script.

A slightly different syntax can be used for `ADD_REMOTE_SERVICES` and its IPv6 variant to allow inbound traffic, e.g.:

```bash
export ADD_LOCAL_SERVICES="4.3.2.1>4711"
```

allows traffic, i.e. from the remote address "4.3.2.1" to the local port "4711".

The script sets few _sysctl_ values.
If unwanted then please comment out the call of _setSysctlValues()_.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out _addHetzner()_.
To append rules onto existing _iptables_ rule set (overwrite is the default) please comment out the call _clearRules()_.

### Metrics

The script [metrics.sh](./metrics.sh) exports DDoS metrics in a Prometheus-formatted file.
The scrape of it is handled by [node_exporter](https://github.com/prometheus/node_exporter).
More details plus few Grafana dashboards are [here](./dashboards/README.md).

### DDoS examples

Graphs¹ of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days
for 2 relays.
A more heavier attack was observed at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
A periodic drop down of the socket count metric, vanishing over time, appeared at
[5th](./doc/network-metric-Dec-05th.svg) of Dec.
Current attacks e.g. at the [7th](./doc/network-metric-Mar-7th.svg) of March are still handled well.
Few more helper scripts were developed to analyze the attack vector.
Look [here](./misc/README.md) for details.

¹ using [sysstat](http://sebastien.godard.pagesperso-orange.fr/)

### More

I used [this](https://github.com/toralf/tor-relays/) Ansible role to deploy and configure Tor relays (server, bridges, snowflake).

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

[orstatus.py](./orstatus.py) prints the _closing reason_ to stdout,
[orstatus-stats.sh](./orstatus-stats.sh) prints/plots statistics ([see this example](./doc/orstatus-stats.sh.txt)) from that.

```bash
orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus &
sleep 3600
orstatus-stats.sh /tmp/orstatus
```

### Check expiration of Tor offline keys

[key-expires.py](./key-expires.py) helps to maintain
[Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/).
It returns the expiration time in seconds of the mid-term signing key, a cronjob could be sth. like this:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/keys/ed25519_signing_cert)
days=$((seconds / 86400))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```

If Tor metrics are enabled then this 1-liner does the similar job (maybe replace `9052` with the metrics port):

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

The python library [Stem](https://stem.torproject.org/index.html) is needed.
Install it either by your package manager -or- use the git sources, e.g.:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

## Search logs for pre-defined text patterns

The script [watch.sh](./watch.sh) helps to constantly monitor the host and Tor log files.
It sends findings via _mailx_.

```bash
log=/tmp/${0##*/}.log

# watch syslog
/opt/torutils/watch.sh /var/log/messages /opt/torutils/watch-messages.txt &>>$log &
# watch Tor
/opt/torutils/watch.sh /var/log/tor/notice.log /opt/torutils/watch-tor.txt -v &>>$log &
```
