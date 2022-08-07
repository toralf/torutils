[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools around a Tor relay.

### Firewall scripts
*ipv4-rules.sh* and *ipv6-rules.sh* blocks ip addresses DDoS'ing the local Tor relays.
They implement 2 rules for IPv4 and IPv6 respectively:

- no more than 2 connections
- no more than 11 connection attempts within 5 minutes

from the same ip address to the local relay ORPort.
A blocked ip address is released after 30 minutes, if the rules are no longer violated. 
The addresses are stored in ipsets named *tor-ddos* and *tor-ddos6* respectively.

Collect data from an ipset eg. by cronjob:

```cron
*/30 * * * * /opt/torutils/ipset-stats.sh -d >> /tmp/ipset4.txt
```
and plot a histogram (i.e. 38 ipsets == last 19 hours):

```console
$> # ipset-stats.sh -p /tmp/ipset4.txt
                                1187 ip addresses, 17937 entries                          
     300 +----------------------------------------------------------------------------+   
         | *       +         +         +        +         +         +         +       |   
         | *                                                                          |   
     250 |-*                                                                        +-|   
         | *                                                                          |   
         | *                           *                                              |   
     200 |-*                           *                                            *-|   
         | *                           *                                            * |   
         | *                           *                                            * |   
     150 |-*                           *                                            *-|   
         | *                           *                                            * |   
         | *                           *                                            * |   
     100 |-*                           *                                            *-|   
         | * *                         *                                            * |   
         | * *                         *                                            * |   
      50 |-* * *                       *                                            *-|   
         | * * * *               *     *                                            * |   
         | * * * * * * * * * * * * * * *        +         *   *     *   *   * * * * * |   
       0 +----------------------------------------------------------------------------+   
         0         5         10        15       20        25        30        35          
                                  occurrence of an ip address                             
```
Check whether Tor relays are catched in an ipset:

```bash
curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - | jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | xargs -r -n 1 > /tmp/relays
ipset list -s tor-ddos | grep -w -f /tmp/relays
```
Here're the iptables statistics for [these](https://metrics.torproject.org/rs.html#search/toralf) 2 relays after 3 days:

```console
$> iptables -nv -L INPUT

Chain INPUT (policy DROP 85112 packets, 5236K bytes)
 pkts bytes target     prot opt in     out     source               destination
 147K   88M DROP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp flags:!0x17/0x02 state NEW /* Wed Aug  3 03:29:33 PM CEST 2022 */
2107K 1335M ACCEPT     all  --  lo     *       0.0.0.0/0            0.0.0.0/0
  50M 2984M            tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 flags:0x17/0x02 recent: SET name: tor-ddos-443 side: source mask: 255.255.255.255
  48M 2885M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 flags:0x17/0x02 recent: UPDATE seconds: 300 hit_count: 15 TTL-Match name: tor-ddos-443 side: source mask: 255.255.255.255 add-set tor-ddos src exist
 373K   93M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 #conn src/32 > 3 add-set tor-ddos src exist
68847   16M ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 match-set tor-authorities src
  37M 2229M            tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 flags:0x17/0x02 recent: SET name: tor-ddos-9001 side: source mask: 255.255.255.255
  36M 2134M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 flags:0x17/0x02 recent: UPDATE seconds: 300 hit_count: 15 TTL-Match name: tor-ddos-9001 side: source mask: 255.255.255.255 add-set tor-ddos src exist
 220K   62M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 #conn src/32 > 3 add-set tor-ddos src exist
73923   17M ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 match-set tor-authorities src
  86M 5392M DROP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set tor-ddos src
3456M 3056G ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443
3116M 2560G ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001
3988M 5076G ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
31962   21M DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID
...
```
### info about Tor relay

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
*ps.py* watches exit ports usage:

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

