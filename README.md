[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg).
This solution uses [ipsets](https://ipset.netfilter.org)² to block malicious ip addresses.
The amount of dropped packets over time is seen in [this](./doc/network-metric-July-3rd.jpg) example.
Look [here](#ddos-examples) for more examples.

¹ see ticket [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and ticket [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093)
of the [Tor project](https://www.torproject.org/).

² An ipset can be easily edited, saved and restored (e.g. for a reboot) using command line tools.

### Quick start

Hint: If there are additional internet service at the relays (except _ssh_) please go to the [Installation](#installation).

Otherwise install the dependencies, e.g. for Ubuntu 22.04:

```bash
sudo apt install iptables ipset jq
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
```

Make a backup of the current iptables _filter_ table (e.g. under Debian run _iptables-save_).
Run:

```bash
sudo ./ipv4-rules.sh test
```

to replace any current content of the iptables _filter_ table with the rule set described below but in a safe mode.
Best is to (re-)start Tor afterwards.
Test in another terminal that you still can ssh into the machine.
Watch the iptables live statistics by:

```bash
sudo watch -t ./ipv4-rules.sh
```

If all works fine for you then run the script again with `start` instead `test`.
Persist the filter rules, e.g. under Debian run _iptables-save_.
If however the above doesn't work for you then please clear the current iptables filter table:

```bash
sudo ./ipv4-rules.sh stop
```

and try out the [Installation](#installation) section.

### Rule set

#### Objectives

- Never touch established connections.¹
- Filter single IPv4 ips, not network segments.²

¹ An attacker capable to spoof ip addresses would trick you to block victim ip addresses.

² An attacker could place a malicious ip within a CIDR range to harm all other addresses in the same network block.
For IPv6 however an /64 IPv6 block is assumed to be assigned to a single host.

#### Details

Generic rules for local network, ICMP, ssh and local user services (if defined) are applied.
Then these rules are applied (in this order) for connection attempts from an ip to the local ORPort:

1. trust ip of Tor authorities and snowflake
2. allow (up to) 8 connections from the same ip if the ip is known to hosts >1 relay
3. block ip for 1 day if the rate of connection attempts is > 6/min in the last 2 minutes¹
4. drop if there are already 2 established connections from the same ip²
5. rate limit new connection attempts to 1 within 2 minutes
6. accept it

¹ Even connection attempts from relays will then be blocked
² This connection limit sounds rigid.
But how likely is it that more than 2 Tor clients from the same ip address do connect to the same guard at the same time?
And Tor relays are unlikely run Tor clients too, right?

### Installation

The instructions belongs to the IPv4 variant.
If the parsing of the Tor config (line [190](./ipv4-rules.sh#L190)) and or SSH (line [19](./ipv4-rules.sh#L19)) doesn't work for you then:

1. define the local running relay(s) at the command line after the keyword `start`, e.g.:

   ```bash
   sudo ./ipv4-rules.sh start 1.2.3.4:443 5.6.7.8:9001
   ```

1. -or- define them within the environment, e.g.:

   ```bash
   sudo CONFIGURED_RELAYS="5.6.7.8:9001 1.2.3.4:443" ./ipv4-rules.sh start
   ```

   (command line values overwrite environment values, `CONFIGURED_RELAYS6` for the IPv6 case).

In addition I do appreciate any issue request [here](https://github.com/toralf/torutils/issues)
-and/or- a GitHub pull request with the fix [here](https://github.com/toralf/torutils/pulls) ;)

To allow inbound traffic to other local service(s), do either:

1. define them in the environment (space separated), e.g.:

   ```bash
   export ADD_LOCAL_SERVICES="27.18.281.828:555"
   ```

   (`ADD_LOCAL_SERVICES6` respectively)

1. -or- explicitely accept any incoming packet which is not filtered out otherwise:

   ```bash
   export DEFAULT_POLICY_INPUT="ACCEPT"
   ```

before you run the script with `start`.

To **append** the rules of this script onto the local _iptables_ rules (**overwrite** of existing rules is the default)
you've to comment out the call _clearRules()_ (line [261](./ipv4-rules.sh#L261)).
The script sets few _sysctl_ values (next line).
As an alternative comment out that line and set them under _/etc/sysctl.d/_.
If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then comment out the call _addHetzner()_ (line [264](./ipv4-rules.sh#L264)).
Rule 3 of the rule set depends on recent data about ip addresses serving more than one Tor relay.
Update this data regularly e.g. hourly via cron:

```bash
sudo ./ipv4-rules.sh update
```

### Metrics

The script [metrics.sh](./metrics.sh) exports data to Prometheus.
Appropriate Grafana dashboards are [here](./dashboards/README.md).
Few more helper scripts were developed to analyze the attack vector, look [here](./misc/README.md) for details.

### DDoS examples

Graphs¹ of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days
for [these](https://nusenu.github.io/OrNetStats/zwiebeltoralf.de.html) 2 relays.
A more heavier attack was observed at [12th](./doc/network-metric-Nov-12th.svg) of Nov.
A periodic drop down of the socket count metric, vanishing over time, appeared at
[5th](./doc/network-metric-Dec-05th.svg) of Dec.
Current attacks e.g. at the [7th](./doc/network-metric-Mar-7th.svg) of March are still handled well.

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

The [Stem](https://stem.torproject.org/index.html) python library is needed too.
Install it either by your package manager -or- use the git sources, e.g.:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
