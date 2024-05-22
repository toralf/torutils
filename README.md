[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) layer, as seen in this metrics:

![image](./doc/dopped_ipv4_2024-03.jpg)

An older example is [here](./doc/network-metric-July-3rd.jpg).

¹ see ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and ticket [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/).

### Quick start

Install packages for _jq_, _ipset_ and _iptables_, e.g. for Ubuntu 22.04:

```bash
sudo apt update
sudo apt install -y jq ipset iptables
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
```

Make a backup of the current iptables _filter_ table and run a quick test:

```bash
sudo /usr/sbin/iptables-save > ./rules.v4
sudo /usr/sbin/ip6tables-save > ./rules.v6
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

If all works fine then run the script with the parameter `start` instead of `test`.

```bash
sudo ./ipv4-rules.sh start
```

and create the following 2 cron jobs:

```cron
# start at reboot

# save in regular intervalls the ips to be blocked, will be fetched at next reboot

```

However, if something failed then restore the previous state:

```bash
sudo ./ipv4-rules.sh stop
sudo /usr/sbin/iptables-restore < ./rules.v4
sudo /usr/sbin/ip6tables-restore < ./rules.v6
```

You can find few more hints in the [Installation](#installation) section to adapt the scripts for your needs.

I do appreciate [issue](https://github.com/toralf/torutils/issues) reports
and GitHub [PR](https://github.com/toralf/torutils/pulls).

### Rule set

#### Objectives

- never touch established connections
- try to not overblock

#### Details

Generic filter rules for the local network, ICMP, ssh and additional services are created.
Then the following rules are applied:

1. trust connection attempt to any port from trusted Tor authorities/Snowflake servers
2. block the source² for 24 hours if the connection attempt rate to the ORPort exceeds > 9/min¹ within last 2 minutes
3. ignore the connection attempt if there are already 9 established connections to the ORPort
4. accept the connection attempt to the ORPort

¹ the value is derived from calculations given in ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636#note_2844146)
² for IPv4 "source" is a regular ip, but for IPv6 the corresponding /80 CIDR block

### Installation

If parsing of the Tor config (_getConfiguredRelays()_) and/or of the SSH config fails (_addCommon()_) then:

1. define the local running relay/s explicitely at the command line after the keyword `start`, e.g.:

   ```bash
   sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
   ```

1. -or- define them as environment variables, e.g.:

   ```bash
   sudo CONFIGURED_RELAYS="5.6.7.8:9001 1.2.3.4:443" ./ipv4-rules.sh start
   ```

   (use `CONFIGURED_RELAYS6` for the IPv6 case).

Specifying command line argument/s takes precedence over an environment variable.
Please use the same syntax to allow inbound traffic to additional <address:port> destinations, e.g.:

```bash
export ADD_LOCAL_SERVICES="2.71.82.81:828 3.141.59.26:53"
```

(use `ADD_LOCAL_SERVICES6` appropriatly) before running the script.

Similar `ADD_REMOTE_SERVICES` and its IPv6 variant can be used to allow inbound traffic
from an address to the local port, e.g.:

```bash
export ADD_LOCAL_SERVICES="4.3.2.1:4711"
```

allows traffic from the (remote) address "4.3.2.1" to local port "4711".

The script sets few _sysctl_ values (following line).
To avoid that please comment out that call.
But consider to set them under _/etc/sysctl.d/_ yoruself.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out the call _addHetzner()_ too.

To append (overwrite is the default) all rules onto existing _iptables_ rule set
please comment out the call _clearRules()_ (near the end of the script at _start)_).

### Operational hints

Before a reboot (or hourly via cron) run

```bash
sudo /etc/conf.d/ipv6-rules.sh save
sudo /etc/conf.d/ipv4-rules.sh save
```

to keep the list of blocked address between restarts.

### Metrics

The script [metrics.sh](./metrics.sh) exports data for Prometheus.
The upload of DDoS metrics is done by [node_exporter](https://github.com/prometheus/node_exporter).
Details and Grafana dashboards are [here](./dashboards/README.md).

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
Take a look [here](./dashboards/README.md) for dashboards.

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
days=$((seconds / 86400))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```

If Tor metrics are enabled then this 1-liner works too (replace `9052` with the actual metrics port if needed):

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

## grep logs for pre-defined text patterns

The script [watch.sh](./watch.sh) helps to monitor a host or its Tor relay.
It sends alarms via SMTP email.

```bash
log=/tmp/${0##*/}.log

# watch syslog
/opt/torutils/watch.sh /var/log/messages /opt/torutils/watch-messages.txt &>>$log &
# watch Tor
/opt/torutils/watch.sh /var/log/tor/notice.log /opt/torutils/watch-tor.txt -v &>>$log &
```
