[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools for a Tor relay.

### block DDoS Tor TLS traffic
*ipv4-rules.sh* and *ipv6-rules.sh* block ip addresses DDoSing a Tor relay and/or the network
by opening dozens of TLS connections to the local ORPort in a short time
([(issue 40636)](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)).
FWIW in a perfect world a Tor client should open just 1 TLS connection and handles all circuits over it.

Technically the ip addresses are stored in a so-called [ipset](https://ipset.netfilter.org/).
The current ruleset blocks about 200-500 addresses at
[these 2](https://metrics.torproject.org/rs.html#search/toralf) relays (each serving about 10K connections).

### info
The script *ipset-stats.sh* plots a histogram from ip set contents:

```bash
for i in 1 2 3 4 5 6
do
  ipset-stats.sh -d > /tmp/ipset.$i.txt
  sleep 1800
done
ipset-stats.sh -p /tmp/ipset.?.txt
```
### info tools
*info.py* gives a summary of a Tor relay:

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
For a monitoring of *exit* connections use *ps.py*:

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

*orstatus.py* logs the reasons of circuit closing events, *orstatus-stats.sh* made stats of its output.

*key-expires.py* returns the seconds till expiration of the mid-term signing key:

```console
$> key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert
7286915
```
### prereq
You need the Python library [Stem](https://stem.torproject.org/index.html) for the python scripts:

```bash
cd /tmp
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
[gnuplot](http://www.gnuplot.info/) for the *-stats.sh* scripts
and [jq](https://stedolan.github.io/jq/) at least for *get-authority-ips.sh*.

