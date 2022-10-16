[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) are designed
to react on DDoS network attack against a Tor relay
(issues [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)).
They do block ips making too much connection (attempts) to the local ORPort.
[This](./metrics-1.svg) and [this](./metrics-2.svg) metric show the effect for continuous and one-time attacks respectively.
The data were gathered by [sysstat](http://pagesperso-orange.fr/sebastien.godard/), a reboot is seen too.

### Quick start
The packages [iptables](https://www.netfilter.org/projects/iptables/) and [jq](https://stedolan.github.io/jq/) are needed.
The call below replaces the previous content of the [filter](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) table of _iptables_ with [this](#rule-set) rule set.

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

The output should look similar to these [IPv4](./iptables-L.txt) and [IPv6](./ip6tables-L.txt) examples.
To reset the filter table, run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule Set
The rules for an inbound connection to the local ORPort are:

1. trust Tor authorities and snowflake
2. block the ip for 30 min if > 5 inbound connection attempts per minute are made _[*]_
3. block the ip for 30 min if > 3 inbound connections are established _[**]_
4. ignore a connection attempt from an ip hosting < 2 relays if 1 inbound connection is already established _[***]_
5. ignore a connection attempt if 2 inbound connections are already established

_[*]_ a 3-digit number of (changing) ips are blocked currently
_[**]_ about 100 ips do "tunnel" rule 4 and 5 daily
_[***]_ Having _jq_ not being installed would still work.
But that would have an impact for 2 remote Tor relays running at the same ip.
If both want to talk to the local filtered ORPort, then the first can initiate its connection.
But now the 2nd has to wait till the local Tor relay opens an outbound connection to it.

### Installation and configuration hints

This document covers IPv4 mostly.
For IPv6 just replace "4" with "6" or simply add "6" where needed and adapt the line numbers.

If the detection of the configured relays doesn't work (line [133](ipv4-rules.sh#L133)), then:
1. specify them at the command line, eg.:
    ```bash
    sudo ./ipv4-rules.sh start 127.0.0.1:443 10.20.30.4:9001
    ```
1. -or- hard code them, i.e. for IPv4 in line [160](ipv4-rules.sh#L160):
    ```bash
     addTor 1.2.3.4:567
    ```
1. -or- create a pull requests to fix it ;)

To allow inbound to additional local network services, either
1. define them in the appropriate environment variable, eg.:
    ```bash
    export ADD_LOCAL_SERVICES="10.20.30.40:25 10.20.30.41:80"
    export ADD_LOCAL_SERVICES6="[dead:beef]:23"
    ```
1. -or- hard code them in line [85](ipv4-rules.sh#L85)
1. -or- edit the default policy in line [6](ipv4-rules.sh#L6) to accept any TCP inbound traffic not matched by any rule:
    ```bash
    iptables -P INPUT ACCEPT
    ```

If you do not use the Hetzner [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/), then
1. remove the `addHetzner()` code, at least its call in line [158](ipv4-rules.sh#L158)
1. -or- just ignore it

## query Tor via its API

[info.py](./info.py) gives a summary of the Tor relay connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gives something like:

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

[orstatus.py](./orstatus.py) logs the reason of Tor circuit closing events.
[orstatus-stats.sh](./orstatus-stats.sh) plots statistics of that output, eg.:

```bash
sudo ./orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus.9051 &
sleep 60
sudo ./orstatus-stats.sh /tmp/orstatus.9051 IOERROR
```

### Prerequisites
An open Tor control port is needed to query the Tor process over its API.
Configure it in `torrc`, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The python library [Stem](https://stem.torproject.org/index.html) is mandatory.
The latest version can be derived by eg.:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

## Misc

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to a local ORPort than a given limit (default: 2).
It should usually list _snowflake-01_ only:

```console
ip                       193.187.88.42           12
relay:65.21.94.13:443            ips:1     conns:12   
```

The script [ipset-stats.sh](./ipset-stats.sh) (package [gnuplot](http://www.gnuplot.info/) is needed)
dumps and visualizes the content of an [ipset](https://ipset.netfilter.org).
The cron example below (for user _root_) shows how to gather data:

```cron
# Tor DDoS stats
*/30 * * * *  d=$(date +\%H-\%M); ~/torutils/ipset-stats.sh -d | tee -a /tmp/ipset4.txt > /tmp/ipset4.$d.txt
```

which can be plotted later by eg.:

```bash
sudo ./ipset-stats.sh -p /tmp/ipset4.?.txt
```

[key-expires.py](./key-expires.py) returns the seconds before the mid-term signing key expires, eg.:

```bash
sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert
7286915
```

(about 84 days).
