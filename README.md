[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools around a Tor relay.

### Tor firewall
*ipv4-rules.sh* and *ipv6-rules.sh* block ip addresses DDoS'ing the local Tor relay(s).
They implement a simple rule for a remote ip address going to a local ORPort:
*Allow only 2 inbound connections.*
Otherwise the ip address gets blocked.
A blocked ip address is released after 30 minutes, if it doesn't violate the rule any longer.

Technically the ip is stored in a so-called [ipset](https://ipset.netfilter.org/).
An ipset can be modified by the command *ipset* or by *iptables*.

After few dumps of an ipset using *ipset-stats.sh* (onto TempFS or `shred -u` the files afterwards), eg.:

```crontab
*/30 * * * * d=$(date +\%H-\%M); /opt/torutils/ipset-stats.sh -d > /tmp/ipset4.$d.txt; /opt/torutils/ipset-stats.sh -D > /tmp/ipset6.$d.txt
```
a histogram about occurrencies versus the amount of ip addresses can be plotted by:

```console
$> # ipset-stats.sh -p /tmp/ipset4.??-??.txt

               34968 occurrences of 2124 ip addresses
  1024 +-----------------------------------------------------+
       |    +     +    +     +    +    +     +    +     +    |
   512 |o+                                                 +-|
       |                                                     |
   256 |-+                                                 +-|
       | o                                      o            |
   128 |-+                                                 o-|
       |  o                                                  |
    64 |-+ o                                               +-|
       |    o                              o      o          |
       |     o o                                 o           |
    32 |-+      oo   o                                     +-|
       |          oo                      o o      oo    o   |
    16 |-+          o oo            o oo     ooo          o+-|
       |                     o     o    o            o o     |
     8 |-+              o     o o o                     o  +-|
       |    +     +    + o  o+ o o+  o +     +    +     +    |
     4 +------------------o----------------------------------+
       0    5     10   15    20   25   30    35   40    45   50
                             occurrence

```
To check whether/how often a Tor relay is among them, run:

```bash
curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - | jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | xargs -r -n 1 > /tmp/relays
grep -h -w -f /tmp/relays /tmp/ipset6.??-??.txt | sort | uniq -c | sort -bn
```
### info about a local running Tor relay

*info.py* gives an overview about the connections:

```console
$> python info.py --ctrlport 9051

ORport 9051
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
*ps.py* watches *exits* connections:

```console
$> ps.py --ctrlport 9051

    port     # opened closed      max                ( :9051, 8998 conns 0.28 sec )
     853     3                      3      1      1  (None)
    5222    42                     42                (Jabber)
    5223     4                      4                (Jabber)
    5269     2                      2                (Jabber)
    6667     4                      4                (IRC)
    7777     3                      3                (None)
```

*orstatus.py* monitors circuit closing events, *orstatus-stats.sh* plots them. *key-expires.py* returns the seconds till the mid-term signing key expires. A cronjob example:

```cron
@daily    n="$(($(key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400))"; [[ $n -lt 23 ]] && echo "Tor signing key expires in <$n day(s)"
```
### prereq
You need the Python library [Stem](https://stem.torproject.org/index.html) for the python scripts:

```bash
cd /tmp
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
[gnuplot](http://www.gnuplot.info/) for the *-stats.sh* scripts
and [jq](https://stedolan.github.io/jq/) to parse JSON data.

