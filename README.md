[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools around a Tor relay.

### Firewall scripts
*ipv4-rules.sh* and *ipv6-rules.sh* blocks ip addresses DDoS'ing the local Tor relays.
They implement 2 rules for IPv4 and IPv6 respectively:

- no more than 3 connections
- no more than 15 connection attempts within 5 minutes

from the same ip address.
A blocked ip address is released after 30 minutes, if the rules are no longer violated. 
The blocked addresses are in stored using ipsets named *tor-ddos* and *tor-ddos6*.

Gather data from those via a cronjob (but do not disclose those data!), eg. by a cronjob:

```crontab
*/30 * * * * /opt/torutils/ipset-stats.sh -d >> /tmp/ipset4.txt
```
Use `-a` and `-A` respectively to anonymise the addresses a little bit.
Plot a histogram:

```console
$> # ipset-stats.sh -p /tmp/ipset4.txt
                                                                                          
                                 948 ip addresses, 9871 entries                           
     250 +----------------------------------------------------------------------------+   
         |    +   +    +   +    +   +    +   +    +   +    +   +    +   +    +   *    |   
         |                                                                   *   *    |   
         |                                                                   *   *    |   
     200 |-+                                                                 *   *  +-|   
         |                                                                   *   *    |   
         |    *                                                              *   *    |   
     150 |-+  *                                                              *   *  +-|   
         |    *                                                              *   *    |   
         |    *                                                              *   *    |   
         |    *                                                              *   *    |   
     100 |-+  *                                                              *   *  +-|   
         |    *                                                              *   *    |   
         |    *                                                              *   *    |   
      50 |-+  *                                                              *   *  +-|   
         |    *   *                                        *   *             *   *    |   
         |    *   *    *   *    *                     *    *   *    *        *   *    |   
         |    *   *    *   *    *   *    *   *    *   *    *   *    *   *    *   *    |   
       0 +----------------------------------------------------------------------------+   
         0    1   2    3   4    5   6    7   8    9   10   11  12   13  14   15  16   17  
                                  occurrence of an ip address                             
```
Here're stats from iptables for 2 relays at the same ip address after about 2 days:

```console
# iptables -nv -L INPUT
Chain INPUT (policy DROP 70762 packets, 4471K bytes)
 pkts bytes target     prot opt in     out     source               destination         
 125K   75M DROP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp flags:!0x17/0x02 state NEW /* Wed Aug  3 03:29:33 PM CEST 2022 */
1893K 1206M ACCEPT     all  --  lo     *       0.0.0.0/0            0.0.0.0/0           
  46M 2737M            tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 flags:0x17/0x02 recent: SET name: tor-ddos-443 side: source mask: 255.255.255.255
  44M 2655M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 flags:0x17/0x02 recent: UPDATE seconds: 300 hit_count: 15 TTL-Match name: tor-ddos-443 side: source mask: 255.255.255.255 add-set tor-ddos src exist
 322K   81M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 #conn src/32 > 3 add-set tor-ddos src exist
45103   11M ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443 match-set tor-authorities src
  34M 2040M            tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 flags:0x17/0x02 recent: SET name: tor-ddos-9001 side: source mask: 255.255.255.255
  33M 1960M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 flags:0x17/0x02 recent: UPDATE seconds: 300 hit_count: 15 TTL-Match name: tor-ddos-9001 side: source mask: 255.255.255.255 add-set tor-ddos src exist
 188K   53M SET        tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 #conn src/32 > 3 add-set tor-ddos src exist
69182   15M ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001 match-set tor-authorities src
  79M 4935M DROP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set tor-ddos src
2848M 2505G ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:443
2585M 2094G ACCEPT     tcp  --  *      *       0.0.0.0/0            65.21.94.13          tcp dpt:9001
3282M 4157G ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
27904   19M DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID
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
*ps.py* continuously monitors exit ports usage:

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

*orstatus.py* monitors closing Tor events and *orstatus-stats.sh* plots them. *key-expires.py* returns the seconds till a mid-term signing key expires. A cronjob example:

```crontab
@daily    n="$(($(key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400))"; [[ $n -lt 23 ]] && echo "Tor signing key expires in <$n day(s)"
```
### more info
You need the Python library [Stem](https://stem.torproject.org/index.html) for the python scripts:

```bash
$> cd <somewhere>
$> git clone https://github.com/torproject/stem.git
$> export PYTHONPATH=$PWD/stem
```
and [gnuplot](http://www.gnuplot.info/) for the *-stats.sh* scripts.

