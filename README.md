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

Gather data from those via a cronjob, eg.:

```crontab
*/30 * * * * /opt/torutils/ipset-stats.sh -d >> /tmp/ipset4.txt
```
and plot a histogram:

```bash
ipset-stats.sh -p /tmp/ipsets4.txt

                                1229 ip addresses, 14978 entries
     350 +----------------------------------------------------------------------------+
         |  *  +  + +  +  +  +  +  +  + +  +  +  +  +  + +  +  +  +  +  +  + +  +  +  |
         |  *                                                                      *  |
     300 |-+*                                                                      *+-|
         |  *                                                                      *  |
     250 |-+*                                                                      *+-|
         |  *                                                                      *  |
         |  *                                                                      *  |
     200 |-+*                                                                      *+-|
         |  *                                                                      *  |
     150 |-+*                                                                      *+-|
         |  *                                                                      *  |
         |  *                                                                      *  |
     100 |-+*                      *                                               *+-|
         |  *  *                   *                                               *  |
      50 |-+*  *                   *                                               *+-|
         |  *  *  *                *                                         *  *  *  |
         |  *  *  * *  *  *  +  *  *  * *  *  *  *  *  + *  *  *  +  +  +  * *  *  *  |
       0 +----------------------------------------------------------------------------+
         0  1  2  3 4  5  6  7  8  9  1 11 12 13 14 15 1 17 18 19 20 21 22 2 24 25 26 27
                                  occurrence of an ip address
```

### info about Tor relay

*info.py* gives an overview about the connections of a relay:

```bash
    python info.py --ctrlport 9051
    0.4.6.0-alpha-dev   uptime: 5-07:14:15   flags: Fast, Guard, HSDir, Running, Stable, V2Dir, Valid

    +------------------------------+------+------+
    | Type                         | IPv4 | IPv6 |
    +------------------------------+------+------+
    | Inbound to our OR from OR    | 1884 |   17 |
    | Inbound to our OR from other | 2649 |    3 |
    | Inbound to our DirPort       |      |      |
    | Inbound to our ControlPort   |    1 |      |
    | Outbound to relay OR         | 3797 |  563 |
    | Outbound to relay non-OR     |    3 |    1 |
    | Outbound exit traffic        |   45 |    8 |
    | Outbound unknown             |   13 |    2 |
    +------------------------------+------+------+
    | Total                        | 8392 |  594 |
    +------------------------------+------+------+

    +------------------------------+------+------+
    | Exit Port                    | IPv4 | IPv6 |
    +------------------------------+------+------+
    | 853                          |    1 |      |
    | 5222 (Jabber)                |   33 |    8 |
    | 5223 (Jabber)                |    4 |      |
    | 5269 (Jabber)                |    2 |      |
    | 6667 (IRC)                   |    2 |      |
    | 7777                         |    3 |      |
    +------------------------------+------+------+
    | Total                        |   45 |    8 |
    +------------------------------+------+------+
```
*ps.py* continuously monitors exit ports usage:

```bash
    ps.py --ctrlport 9051

    port     # opened closed      max                ( :9051, 8998 conns 0.28 sec )
     853     3                      3      1      1  (None)
    5222    42                     42                (Jabber)
    5223     4                      4                (Jabber)
    5269     2                      2                (Jabber)
    6667     4                      4                (IRC)
    7777     3                      3                (None)
```

*orstatus.py* monitors closing Tor events and *orstatus-stats.sh* plots them:

```bash
    orstatus.py --ctrlport 9051 | tee x

    DONE         6E642BD08A5D687B2C55E35936E3272636A90362  <snip>  9001 v4 0.3.5.11
    IOERROR      C89F338C54C21EDA9041DC8F070A13850358ED0B  <snip>   443 v4 0.4.3.5
```
*key-expires.py* returns the seconds till a mid-term signing key expires. A cronjob example:

```crontab
@daily    n="$(($(key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400))"; [[ $n -lt 23 ]] && echo "Tor signing key expires in <$n day(s)"
```
### more info
You need the Python lib Stem (https://stem.torproject.org/index.html) for the python scripts:

```bash
export PYTHONPATH=<path to stem>
```

