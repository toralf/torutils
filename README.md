[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools around a Tor relay.

### Firewall
*ipv4-rules.sh* and *ipv6-rules.sh* block ip addresses DDoS'ing local Tor relay(s).
They implement a simple rule for a remote ipv4/6 address connecting to the local ORPort:
*Allow only 3 inbound connections.*
Otherwise the ip address is for the next 30 min not allowed to open any new connection.

Technically the ip is stored in an [ipset](https://ipset.netfilter.org/).
Such a set can be modified both by the command *ipset* or by *iptables*.

After few dumps of the content of an ipset using *ipset-stats.sh* (to TempFS and/or `shred -u` the files afterwards), eg.:

```crontab
*/30 * * * * d=$(date +\%H-\%M); /opt/torutils/ipset-stats.sh -d > /tmp/ipset4.$d.txt; /opt/torutils/ipset-stats.sh -D > /tmp/ipset6.$d.txt
```
a histogram of occurrencies versus their amount of ip addresses can be plotted by:

```console
$> # ipset-stats.sh -p /tmp/ipset4.??-??.txt

               26553 occurrences of 1877 ip addresses            
  1024 +-----------------------------------------------------+   
       |o   +     +    +     +    +    +     +    +     +    |   
   512 |-+                                                 +-|   
       |                                                     |   
   256 |-+                                                 +-|   
       |                                                     |   
   128 |-o                                                 o-|   
       |                                                  o  |   
    64 |-+o                                                +-|   
       |   o                                                 |   
       |    o  o                                         o   |   
    32 |-+      o                                          +-|   
       |     o   o  o                            oo     o    |   
    16 |-+        oo  oo oo    o              o o  o       +-|   
       |             o  o    o              oo      o        |   
     8 |-+                  o o o o oo oo oo         o     +-|   
       |    +     +    +     +   o+   o+     + o  +     +    |   
     4 +---------------------------o-------------------o-----+   
       0    5     10   15    20   25   30    35   40    45   50  
                             occurrence                          

```
### info

*info.py* gives an connection overview of a local Tor relay:

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
For realtime watching of *exit* connections use *ps.py*:

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

*orstatus.py* logs in realtime circuit closing events, *orstatus-stats.sh* plots them later.
*key-expires.py* returns the seconds till expiration of the mid-term signing key.
A cronjob example:

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

