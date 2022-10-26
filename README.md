[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) were made
to protect a Tor relay against a DDoS attack at TCP/IP level. _[*]_
They do block ip addresses making too much connection (attempts) to the local ORPort.
The data in [these](./doc/network-metric.svg) metrics show how the different DDoS attacks
were handled in practise (socks) while CPU (green line belongs to
[these](https://metrics.torproject.org/rs.html#details/509EAB4C5D10C9A9A24B4EA0CE402C047A2D64E6)
2 Tor processes) and rx/tx seems to operate normal.

_[*]_ Details are in issue [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)
of the [Tor project](https://www.torproject.org/).

### Quick start
The package [iptables](https://www.netfilter.org/projects/iptables/) is needed.
If it is installed, run:

```bash
# wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
# chmod +x ./ipv4-rules.sh
git clone https://github.com/toralf/torutils
cd torutils
sudo ./ipv4-rules.sh start
```

to configure the _filter_  table of [iptables](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) using the rule set below. Best is to (re-)start Tor afterwards.
The live statistics are given by:

```bash
sudo watch -t ./ipv4-rules.sh
```

The output should look similar to this [IPv4](./doc/iptables-L.txt) or this [IPv6](./doc/ip6tables-L.txt) example respectively.
To clear the _filter_ table, run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule set

Established connections will not be touched.
Outbounds connections will not be touched.
Only the inbound connection attempts are controlled.
Therefore rules for an ip, connecting to the local ORPort, are applied:

1. trust Tor authorities and snowflake
1. block for 30 min if it makes > 8 connection attempts per minute
1. limit connection attempts to 1/min
1. ignore a connection attempt if > 4 connections are already established
1. accept remaining connection attempts

In addition generic rules for local network interfaces, ICMP, ssh and user defined services are applied.

### Configuration
The instructions do belong to the IPv4 variant.
They do apply in a similar way for the IPv6 case.

If the parsing of _torrc_ doesn't work for you (line [130](ipv4-rules.sh#L130)) then:
1. define the relay(s) space separated in this environment variable before applying the rule set, eg.:
    ```bash
    export CONFIGURED_RELAYS="3.14.159.26:535"
    export CONFIGURED_RELAYS6="[cafe::dead:beef]:4711"
    ```
1. -or- create a pull requests to fix the code ;)


Same happens for additional local network services:
1. define them space separated in this environment variable before applying the rule set, eg.:
    ```bash
    export ADD_LOCAL_SERVICES="2.718.281.828:459"
    export ADD_LOCAL_SERVICES6="[edda:fade:affe:baff:eff:eff]:12345"
    ```
1. -or- append your iptables rules to the _filter_ table
1. -or- open the iptables chain _INPUT_ in line [6](ipv4-rules.sh#L6):
    ```bash
    iptables -P INPUT ACCEPT
    ```
    I won't recommended that however.

If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't needed, then
1. remove the _addHetzner()_ code (line [87ff](ipv4-rules.sh#L87)) and its call in line [156](ipv4-rules.sh#L156)
1. -or- just ignore it

### Further settings

I have set the _uname_ limit for the Tor process to _60000_.
Furthermore I configured few sysctl values in _/etc/sysctl.d/local.conf_:

```console
net.ipv4.ip_local_port_range = 2000 63999
kernel.kptr_restrict = 1
kernel.perf_event_paranoid = 3
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
user.max_user_namespaces = 0
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
```

### Misc

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to the local ORPort than a given limit.
It should usually list _snowflake-01_ only:

```bash
sudo ./ddos-inbound.sh -l 4
```

The script [ipset-stats.sh](./ipset-stats.sh) (needs package [gnuplot](http://www.gnuplot.info/))
dumps the content of an [ipset](https://ipset.netfilter.org) and plots those data.
[This](./doc/crontab.txt) crontab example (of user _root_) shows how to gather data,
from which histograms like the one below can be plotted by:

```bash
sudo ./ipset-stats.sh -p /tmp/ipset4.*.txt
```

[orstatus.py](./orstatus.py) logs the reason of Tor circuit closing events.
[orstatus-stats.sh](./orstatus-stats.sh) prints and/or plots statistics from the output, eg.:

```bash
sudo ./orstatus-stats.sh /tmp/orstatus.9051 TLS_ERROR
```

A histogram over the timeout values of all ips of an ipset (i.e. `tor-ddos`) is taken by:

```bash
tmpfile=$(mktemp /tmp/XXXXXX);  ipset list tor-ddos -s | grep ' timeout ' | grep -v ' inet' | awk '{ print $3 }' | sort -bn > $tmpfile; gnuplot -e 'set terminal dumb; set border back; set key noautotitle; set title "ips per timeout"; set xlabel "ips"; plot "'$tmpfile'" pt "o";'; rm $tmpfile
```

## Query Tor via its API

[info.py](./info.py) gives a summary of all  connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gives here:

```console
 0.4.8.0-alpha-dev   uptime: 2-08:25:40   flags: Fast, Guard, Running, Stable, V2Dir, Valid

+------------------------------+-------+-------+
| Type                         |  IPv4 |  IPv6 |
+------------------------------+-------+-------+
| Inbound to our OR from relay |  2269 |   809 |
| Inbound to our OR from other |  2925 |    87 |
| Inbound to our ControlPort   |     2 |       |
| Outbound to relay OR         |  2823 |   784 |
| Outbound to relay non-OR     |     4 |     4 |
| Outbound exit traffic        |       |       |
| Outbound unknown             |    40 |    29 |
+------------------------------+-------+-------+
| Total                        |  8063 |  1713 |
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
The latest version can be derived by eg.:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

## Tor offline keys
If you do use [Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/)
then [key-expires.py](./key-expires.py) helps you to not miss the key rotation timeline.
It returns the seconds before the mid-term signing key expires, eg:

```bash
seconds=$(/opt/torutils/key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```
