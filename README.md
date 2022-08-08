[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools around a Tor relay.

### Firewall scripts
*ipv4-rules.sh* and *ipv6-rules.sh* blocks ip addresses DDoS'ing the local Tor relays.
They implement 2 rules for IPv4 and IPv6 respectively for a remote ip address connecting to the local ORPort :

- <=  2 inbound connections (if there's >1 relay running), 1 otherwise
- <= 11 new inbound connection attempts within 5 minutes

A blocked ip address is released after 30 minutes, if it no longer violates the rules. 
Technically addresses are stored in a so-called [ipset](https://ipset.netfilter.org/).

An ipset can be modified by the command *ipset* itself or by *iptables*.

`ipset-stats.sh` is used to list ip addresses (ie. a crontab entry):

```bash
*/30 * * * * d=$(date +\%H-\%M); /opt/torutils/ipset-stats.sh -d > /tmp/ipset4.$d.txt; /opt/torutils/ipset-stats.sh -D > /tmp/ipset6.$d.txt
```
and/or to plot them:

```console
$> # ipset-stats.sh -p /tmp/ipset4.??-??.txt

                                 2954 ip addresses, 19860 hits                            
     900 +----------------------------------------------------------------------------+   
         |    *    +          +         +         +         +          +         +    |   
     800 |-+  *                                                                     +-|   
         |    *                                                                       |   
     700 |-+  *                                                                     +-|   
         |    *                                                                       |   
     600 |-+  *                                                                     +-|   
         |    *                                                                  *    |   
     500 |-+  *                                                                  *  +-|   
         |    *                                                                  *    |   
     400 |-+  *                                                                  *  +-|   
         |    *                                                                  *    |   
     300 |-+  *                                                                  *  +-|   
         |    *                                   *                              *    |   
     200 |-+  *    *                              *                              *  +-|   
         |    *    *                         *    *                         *    *    |   
     100 |-+  *    *    *     *    *    *    *    *    *    *    *     *    *    *  +-|   
         |    *    *    *     *    *    *    *    *    *    *    *     *    *    *    |   
       0 +----------------------------------------------------------------------------+   
         0         2          4         6         8         10         12        14       
                                  occurrence of an ip address                             
```
Check whether Tor relays are catched in an ipset:

```bash
curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - | jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | xargs -r -n 1 > /tmp/relays
ipset list -s tor-ddos | grep -w -f /tmp/relays
```
### info about Tor relay connections

*info.py* gives an overview about the connections of a relay:

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
*ps.py* watches Tor exits connections:

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

*orstatus.py* monitors Tor closing events and *orstatus-stats.sh* plots them. *key-expires.py* returns the seconds till the mid-term signing key expires. A cronjob example:

```cron
@daily    n="$(($(key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400))"; [[ $n -lt 23 ]] && echo "Tor signing key expires in <$n day(s)"
```
### more info
You need the Python library [Stem](https://stem.torproject.org/index.html) for the python scripts:

```bash
cd /tmp
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
and [gnuplot](http://www.gnuplot.info/) for the *-stats.sh* scripts.
[jq](https://stedolan.github.io/jq/) is a good JSON parser.

