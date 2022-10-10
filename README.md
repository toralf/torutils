[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

### Goal

To reduce the DDoS impact at TCP/IP level for a Tor relay
use [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) respectively.
Currently a 3-digit-number of ips gets blocked at
[these](https://metrics.torproject.org/rs.html#search/toralf) 2 relays, each serving about 10K connections.
The rules for an inbound ip are:

1. trust Tor authorities
1. block the ip for the next 30 min if more than 6 inbound connection attempts per minute are made
1. block the ip for the next 30 min if more than 3 inbound connections are established
1. ignore a connection attempt from an ip hosting < 2 relays if 1 inbound connection is already established
1. ignore a connection attempt if 2 inbound connections are already established

[Here're](./sysstat.svg) metrics to show the effect (data collected with [sysstat](http://pagesperso-orange.fr/sebastien.godard/)).
More details might be found in Issue [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636) and Issue  [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393).

All examples below are for the IPv4 case. For IPv6 replace `4` with `6` in `ipv4-rules.sh`.

### Quick Start

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

Then (re-)start Tor.
The current settings of your firewall are printed by:

```bash
sudo ./ipv4-rules.sh
```

They should look similar to these [IPv4](./iptables-L.txt) and [IPv6](./ip6tables-L.txt) examples.
The packages [iptables](https://www.netfilter.org/projects/iptables/) and [jq](https://stedolan.github.io/jq/) are required,
eg. for Debian run:

```bash
sudo apt-get install iptables jq
```
### Stop
To reset the local firewall entirely, run:
```bash
sudo ./ipv4-rules.sh stop
```

### Monitoring

The script _ipset-stats.sh_ dumps and visualizes the content of the used and so-called [ipsets](https://ipset.netfilter.org).
In the example below the blocked ips are dumped half-hourly over 3 hours.
Afterwards their distribution is plotted:

```bash
for i in 1 2 3 4 5 6
do
  sudo ./ipset-stats.sh -d > /tmp/ipset4.$i.txt   # dump content of IPv4 ipset "tor-ddos"
  sudo ./ipset-stats.sh -D > /tmp/ipset6.$i.txt   # dump content of IPv6 ipset "tor-ddos6"
  sleep 1800
done
sudo ./ipset-stats.sh -p /tmp/ipset4.?.txt  # plot histogram from IPv4 data set
sudo ./ipset-stats.sh -p /tmp/ipset6.?.txt  # "                   IPv6 "
```

The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

### Detailed Installation and Configuration

If Tor is behind a NAT, listens at another ip or if 2 Tor services do run at the same ip, then:
1. specify the Tor ORPort(s) as parameter/s, eg.
    ```bash
    sudo ./ipv4-rules.sh start 127.0.0.1:443 10.20.30.4:9001
    ```
1. -or- configure them, i.e. for IPv4 in line [142](ipv4-rules.sh#L142):
    ```bash
    relays=${*:-"0.0.0.0:443"}
    ```

For additional local running services, either
1. set them before you start the script, eg.:
    ```bash
    export ADD_LOCAL_SERVICES="10.20.30.40:25 10.20.30.41:80"
    export ADD_LOCAL_SERVICES6="[dead:beef]:23"
    ```
1. -or- configure them directly, i.e. for IPv4 in line [81](ipv4-rules.sh#L81)
1. -or- change the default policy, i.e. for IPv4 in line [7](ipv4-rules.sh#L7):
    ```bash
    iptables -P INPUT ACCEPT
    ```

If you do not use the [Hetzner monitoring](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/), then
1. ignore the firewall rule
1. -or- remove the `addHetzner()` code, at least line [140](ipv4-rules.sh#L140)

## query Tor via its API

A configured control port in `torrc` is needed to query the Tor process over its API, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The python library [Stem](https://stem.torproject.org/index.html) is mandatory.
Often it has to be installed manually:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

The package [gnuplot](http://www.gnuplot.info/) is needed if graphs shall be plotted.
_info.py_ gives a summary of a Tor relay:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

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

For a monitoring of _exit_ connections use _ps.py_:

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

```console
    port     # opened closed      max                ( "" ::1:9051, 8998 conns 0.28 sec )
     853     3                      3      1      1  (None)
    5222    42                     42                (Jabber)
    5223     4                      4                (Jabber)
    5269     2                      2                (Jabber)
    6667     4                      4                (IRC)
    7777     3                      3                (None)
```

_orstatus.py_ logs the reasons of circuit closing events, _orstatus-stats.sh_ made stats of its output, eg.:

```bash
sudo ./orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus.9051
```

after a certain time press Ctrl-C (or let it run and switch to another terminal).
Take a look eg. at the distribution of _IOERROR_:

```bash
sudo ./orstatus-stats.sh /tmp/orstatus.9051
```

or directly grep for the most often occurrences, eg. of _TLS_ERROR_:

```bash
grep 'TLS_ERROR' /tmp/orstatus.9051 | awk '{ print $3 }' | sort | uniq -c | sort -bn | tail
```

_key-expires.py_ returns the time in seconds when the mid-term signing key will expire, eg.:

```bash
sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert
7286915
```

, this is in days (rounded to an integer):

```bash
expr 7286915 / 24 / 3600
84
```
