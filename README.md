[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The script [ipv4-rules.sh](./ipv4-rules.sh) is designed to lower the impact of a DDoS
at [layer-3](https://www.infoblox.com/glossary/layer-3-of-the-osi-model-network-layer/)
against a Tor relay.
Currently a 3-digit-number of ips gets blocked if they make too much connection (attempts) to the local ORPort
which corresponds to a 4-digit number of local ports not being opened.
[Here're](./sysstat.svg) metrics to show the effect (data gathered by [sysstat](http://pagesperso-orange.fr/sebastien.godard/)).
Details are in the issues [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393).

### Quick start
The packages [iptables](https://www.netfilter.org/projects/iptables/) and [jq](https://stedolan.github.io/jq/) are needed.

The call below replaces the previous content of the [filter](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) table of _iptables_ with rule set described [here](#rule-set).

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

Best is to (re-)start Tor afterwards.
The live statistics of your network rules can be shown by:

```bash
sudo watch -t ./ipv4-rules.sh
```

The output should look similar to the [IPv4](./iptables-L.txt) and [IPv6](./ip6tables-L.txt) example.
To reset the filter table, run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule Set
The rules for an inbound connecting to the local ORPort are:

1. trust Tor authorities
2. block the ip for the next 30 min if > 6 inbound connection attempts per minute are made
3. block the ip for the next 30 min if > 3 inbound connections are established
4. ignore a connection attempt from an ip hosting < 2 relays if 1 inbound connection is already established [1]
5. ignore a connection attempt if 2 inbound connections are already established [2]

[1] Having _jq_ not being installed and deactivating its code would work but would half the cost of a DDoS attempt.

[2] Deleting rule 4 and changing "2" to "1" in rule 5 would work.
But that would have an impact for 2 remote Tor relays running at the same ip.
If both want to talk to the local filtered ORPort, then one of both can initiate its connection to the local ORPort.
But now the other remote Tor relay has to wait till the local Tor relay opens an outbound connection to it.

### Installation and configuration hints

This document covers the IPv4 part only. For IPv6 usually just replace "4" with "6" or simply add "6" where needed.

If the detection of the configured relays doesn't work (line [133](ipv4-rules.sh#L133)), then:
1. specify them at the command line, eg.:
    ```bash
    sudo ./ipv4-rules.sh start 127.0.0.1:443 10.20.30.4:9001
    ```
1. -or- hard code them, i.e. for IPv4 in line [159](ipv4-rules.sh#L159):
    ```bash
     addTor 1.2.3.4:567
    ```
1. -or- create a pull requests to fix it ;)

To enable additional local services, either
1. define them as environment variables, eg.:
    ```bash
    export ADD_LOCAL_SERVICES="10.20.30.40:25 10.20.30.41:80"
    export ADD_LOCAL_SERVICES6="[dead:beef]:23"
    ```
1. -or- hard code them, i.e. for IPv4 in line [85](ipv4-rules.sh#L85)
1. -or- edit the default policy, i.e. for IPv4 in line [6](ipv4-rules.sh#L6) to accept any TCP inbound traffic not matched by any rule:
    ```bash
    iptables -P INPUT ACCEPT
    ```

If you do not use the Hetzner [monitoring service](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/), then
1. remove the `addHetzner()` code, at least its call in line [157](ipv4-rules.sh#L157)
1. -or- just ignore it

## query Tor via its API

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

_orstatus.py_ logs the easons of a circuit closing event, _orstatus-stats.sh_ makes and plots stats of its output, eg.:

```bash
sudo ./orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus.9051
```

After a certain time switch to another terminal (or press Ctrl-C) and take a look, eg. at the distribution of _IOERROR_:

```bash
sudo ./orstatus-stats.sh /tmp/orstatus.9051 _IOERROR_
```

or directly grep for the most often occurrences of a reason, eg.:

```bash
grep 'TLS_ERROR' /tmp/orstatus.9051 | awk '{ print $3 }' | sort | uniq -c | sort -bn | tail
```

### Prerequisites
An open Tor control port is needed to query the Tor process over its API.
Configure it in `torrc`, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The python library [Stem](https://stem.torproject.org/index.html) is mandatory.
Th elatest version can be used by eg.:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

The package [gnuplot](http://www.gnuplot.info/) is needed if graphs shall be plotted.

## Misc

_ddos-inbound.sh_ lists ips, where the # of inbound connections exceeds the given limit.
It should usually list _snowflake-01_ only:

```console
ip         193.187.88.42                               12
relay:65.21.94.13:443                                      ips:1     conns:12   

ip         193.187.88.42                               12
relay:65.21.94.13:9001                                     ips:1     conns:12   
```

The script _ipset-stats.sh_ dumps and visualizes the content of an [ipset](https://ipset.netfilter.org).
In the example below the blocked ips are dumped half-hourly over 3 hours.
Afterwards their distribution is plotted (ackage [gnuplot](http://www.gnuplot.info/) is needed):

```bash
for i in 1 2 3 4 5 6
do
  sudo ./ipset-stats.sh -d > /tmp/ipset4.$i.txt   # IPv4, default ipset "tor-ddos"
  sudo ./ipset-stats.sh -D > /tmp/ipset6.$i.txt   # IPv6, default ipset "tor-ddos6"
  sleep 1800
done
sudo ./ipset-stats.sh -p /tmp/ipset4.?.txt  # plot histogram from dumped IPv4 data
sudo ./ipset-stats.sh -p /tmp/ipset6.?.txt  # "                          IPv6 "
```

_key-expires.py_ returns the seconds before the mid-term signing key expires, eg.:

```bash
sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert
7286915
```

(about 84 days).
