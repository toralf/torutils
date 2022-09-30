[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils

Few tools for a Tor relay.

## block DDoS traffic

_ipvX-rules.sh_ blocks ip addresses DDoSing a Tor relay
([Torproject issue 40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)).
Currently about 100-600 addresses are blocked at
[these](https://metrics.torproject.org/rs.html#search/toralf) 2 relays (each serving about 10K connections).

The rules for an inbound ip are:

1. trust Tor authorities
1. block the ip for the next 30 min if more than 6 inbound connection attempts per minute were made
1. block the ip for the next 30 min if more than 3 inbound connections are established
1. ignore a connection attempt from an ip hosting < 2 relays if 1 inbound connection is already established 
1. ignore a connection attempt if 2 inbound connections are already established

[Here're](./sysstat.svg) network statistics got with [sysstat](http://pagesperso-orange.fr/sebastien.godard/).

The local (live) statistics of the working rules can be watched via:

```bash
watch ipv4-rules.sh
```
The script _ipset-stats.sh_ dumps or visualize the [ipset](https://ipset.netfilter.org), which holds the blocked ip addresses:

```bash
for i in 1 2 3 4 5 6
do
  ipset-stats.sh -d > /tmp/ipset.$i.txt
  sleep 1800
done
ipset-stats.sh -p /tmp/ipset.?.txt
```

## info tools

_info.py_ gives a summary of a Tor relay:

```console
$> info.py --ctrlport 9051
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

```console
$> ps.py --ctrlport 9051

    port     # opened closed      max                ( "" ::1:9051, 8998 conns 0.28 sec )
     853     3                      3      1      1  (None)
    5222    42                     42                (Jabber)
    5223     4                      4                (Jabber)
    5269     2                      2                (Jabber)
    6667     4                      4                (IRC)
    7777     3                      3                (None)
```

_orstatus.py_ logs the reasons of circuit closing events, _orstatus-stats.sh_ made stats of its output.

_key-expires.py_ returns the seconds till expiration of the mid-term signing key:

```console
$> key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert
7286915
```

## prereq

You need [jq](https://stedolan.github.io/jq/) for _ipvX-rules.sh_,
[Stem](https://stem.torproject.org/index.html) for the python scripts:

```bash
cd /tmp
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
and [gnuplot](http://www.gnuplot.info/) for  _*-stats.sh_.

