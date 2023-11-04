[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) layer ([example](./doc/network-metric-July-3rd.jpg)).
Look [here](#ddos-examples) for more examples.

¹ see ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and ticket [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/).

### Quick start

If there are additional internet service at the relays (except _ssh_) please go to the [Installation](#installation) section.
Otherwise install the dependencies, e.g. for Ubuntu 22.04:

```bash
sudo apt update
sudo apt install -y iptables ipset jq
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
```

Make a backup of the current iptables _filter_ table and run a test:

```bash
sudo /usr/sbin/iptables-save > ./rules.v4
sudo /usr/sbin/ip6tables-save > ./rules.v6
sudo ./ipv4-rules.sh test
```

Best is to stop the Tor service(s), flush the connection tracking table:

```bash
sudo /usr/sbin/conntrack -F
```

and to start the Tor service(s).
Then check in another terminal that ssh still works.
Then check the reachability of all of your other services.
Watch the iptables live statistics by:

```bash
sudo watch -t ./ipv4-rules.sh
```

If all works fine then run the script again with `start` instead `test`
and persist the filter rules, e.g. under Debian into `/etc/iptables/`.

However, if the above doesn't work for you then please stop it and restore the previous state:

```bash
sudo ./ipv4-rules.sh stop
sudo /usr/sbin/iptables-restore < ./rules.v4
sudo /usr/sbin/ip6tables-restore < ./rules.v6
```

You might try out the [Installation](#installation) section to adapt the scripts for your system.
I do appreciate [issue](https://github.com/toralf/torutils/issues) reports
and GitHub [pull](https://github.com/toralf/torutils/pulls) request reqpectively.

### Rule set

#### Objectives

- never touch established connections
- IPv4: filter single IPv4 ips, IPv6: filter /64 network segments
- the attack threat dictates the rules of the game

#### Details

Generic rules for local network, ICMP, ssh and local user services (if defined) are applied.
Then these rules are applied (in this order) for an connection attempt from an ip to the local ORPort:

1. trust Tor authorities and Snowflake servers
2. allow (up to) 8 connections in parallel if the ip is known to host Tor relay(s)
3. block for 1 day if the connection attempt rate exceeds > 10/min within last 2 minutes
4. drop if there are already 9 established connections from the same ip¹
5. accept it

¹ calculation examples given by trinity-1686n in [ticket 40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636#note_2844146)

### Installation

If the parsing of the Tor config (_getConfiguredRelays()_) and/or of the SSH config fails (_addCommon()_), then:

1. define the local running relay/s explicitely at the command line after the keyword `start`, e.g.:

   ```bash
   sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
   ```

1. -or- define them as environment variables, e.g.:

   ```bash
   sudo CONFIGURED_RELAYS="5.6.7.8:9001 1.2.3.4:443" ./ipv4-rules.sh start
   ```

   (`CONFIGURED_RELAYS6` for the IPv6 case).

A command line value takes precedence over the environment variable.
To allow inbound traffic to additional local port/s, then define them in the environment (space separated), e.g.:

```bash
export ADD_LOCAL_SERVICES="2.71.82.81:828 3.141.59.26:53"
```

(`ADD_LOCAL_SERVICES6` respectively) before you run the script.
To append the rules onto existing _iptables_ rules (overwrite is the default)
you've to comment out the call _clearRules()_ (near the end of the script at _start)_).
The script sets few _sysctl_ values (following line).
To avoid that comment out that call, but consider to set them under _/etc/sysctl.d/_.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out the call _addHetzner()_ too.

### Operational hints

Before reboot run

```bash
sudo /etc/conf.d/ipv6-rules.sh save
sudo /etc/conf.d/ipv4-rules.sh save
```

to feed rule 3 with recent data at restart.
Rule 2 depends on recent data about ip addresses serving more >1 Tor relay.
Update this data regularly, e.g. hourly via a cron job:

```bash
sudo ./ipv4-rules.sh update
```

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

## watch

I do prefer simple and stupid solutions.
To watch the healthyness of my Tor relays I do use [watch.sh](./watch.sh) and its 2 pattern files.
I start it at reboot via

```bash
log=/tmp/${0##*/}.log

/opt/torutils/watch.sh /var/log/messages /opt/torutils/watch-messages.txt &>>$log &
sleep 1

for i in {1..5}
do
  /opt/torutils/watch.sh /var/log/tor/notice$i.log /opt/torutils/watch-tor.txt -v &>>$log &
done
```
