[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils

Few tools for a Tor relay.

## block DDoS traffic

### rule set

_ipvX-rules.sh_ blocks ip addresses DDoSing a Tor relay
([Torproject issue 40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)).
Currently a 3-digit-number of addresses are blocked at
[these](https://metrics.torproject.org/rs.html#search/toralf) 2 relays (each serving about 10K connections).

The rules for an inbound ip are:

1. trust Tor authorities
1. block the ip for the next 30 min if more than 6 inbound connection attempts per minute are made
1. block the ip for the next 30 min if more than 3 inbound connections are established
1. ignore a connection attempt from an ip hosting < 2 relays if 1 inbound connection is already established
1. ignore a connection attempt if 2 inbound connections are already established

[Here're](./sysstat.svg) few metrics to show the effect (data collected with [sysstat](http://pagesperso-orange.fr/sebastien.godard/)).

### installation
You've to install [iptables](https://www.netfilter.org/projects/iptables/) (which should install [ipset](https://ipset.netfilter.org) too), eg.:

```bash
sudo apt-get install iptables
```

for Debian installer systems.
Furthermore, [jq](https://stedolan.github.io/jq/) is needed by the _ipvX-rules.sh_ scripts and [gnuplot](http://www.gnuplot.info/) to plot histograms by the _\*-stats.sh_ scripts.

Configure your relay(s) explicitly, eg. in `ipv4-rules.sh` line [122](ipv4-rules.sh#L122) for IPv4:

```bash
relays="<ip address>:<or port>"
```
If your hoster is not Hetzner or you didn't use their monitoring then delete the code for `addHetzner()`.

If you have additional network services, then open their inbound ports in the function `addMisc()` too
-or- remove `addMisc()` and simply set the default policy for the chain `INPUT` to `ACCEPT` in function `addCommon()`:

```bash
iptables -P INPUT ACCEPT
```


### start/stop

The IPv4 and IPv6 rules have to be started separately:

```bash
sudo ./ipv4-rules.sh start
sudo ./ipv6-rules.sh start
```

Tor should be started after this.
To remove the rules you've to replace `start` with `stop`. This does not need a restart of Tor.

### monitoring

The current settings of your firewall can be seen via (use _ip6tables_ for the IPv6 variant):

```bash
sudo iptables -nv -L -t raw
sudo iptables -nv -L -t filter
```

or run the script without a parameter, eg. for IPv4:

```bash
sudo ./ipv4-rules.sh
```

Here are example outputs for [IPv4](./iptables-L.txt) and [IPv6](./ip6tables-L.txt) respectively.

The script _ipset-stats.sh_ dumps and visualizes ipset data (default: the ipset of the blocked ips).
In the example below it is run half-hourly for 3 hours. Afterwards the results are plotted:

```bash
for i in 1 2 3 4 5 6
do
  sudo ./ipset-stats.sh -d > /tmp/ipset4.$i.txt   # dump content of IPv4 ipset "tor-ddos"
  sudo ./ipset-stats.sh -D > /tmp/ipset6.$i.txt   # dump content of IPv6 ipset "tor-ddos6"
  sleep 1800
done
sudo ./ipset-stats.sh -p /tmp/ipset4.?.txt  # plot histogram from input data
sudo ./ipset-stats.sh -p /tmp/ipset6.?.txt  # "
```

## query Tor process via its API

A configured control port in `torrc` is needed to query the Tor process over its API, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

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

_orstatus.py_ logs the reasons of circuit closing events, _orstatus-stats.sh_ made stats of its output.
Run it in a terminal, (set _PYTHONPATH_ before) eg.:

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
which are about 84 days (rounded to nearest lower integer), eg.:
```bash
expr 7286915 / 24 / 3600
84
```

### Installation

The [Stem](https://stem.torproject.org/index.html) library (for the python scripts) is needed and often have to be installed manually:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

Furthermore install [gnuplot](http://www.gnuplot.info/).
