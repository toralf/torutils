[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools around a Tor relay.

### gather data from a Tor process:

*info.py* gives an overview about the connections of a relay:

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

*ps.py* continuously monitors exit ports usage:

    ps.py --ctrlport 9051

    port     # opened closed      max                ( :9051, 8998 conns 0.28 sec )
     853     3                      3      1      1  (None)
    5222    42                     42                (Jabber)
    5223     4                      4                (Jabber)
    5269     2                      2                (Jabber)
    6667     4                      4                (IRC)
    7777     3                      3                (None)

*orstatus.py* monitors closing events:

    orstatus.py --ctrlport 9051

    DONE         6E642BD08A5D687B2C55E35936E3272636A90362  <snip>  9001 v4 0.3.5.11
    IOERROR      C89F338C54C21EDA9041DC8F070A13850358ED0B  <snip>   443 v4 0.4.3.5

*key-expires.py* warns if an offline key has to renew its mid-term signing keys, an cronjob example:

```crontab
@daily    n="$(($(key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400))"; [[ $n -lt 23 ]] && echo "Tor signing key expires in <$n day(s)"
```
### more info
You need the Python lib Stem (https://stem.torproject.org/index.html) for the python scripts:
```bash
export PYTHONPATH=<path to stem>
```

