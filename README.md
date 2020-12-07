# torutils
Few tools around a Tor relay.

### gather data from a Tor process:

*info.py* gives an overview about the connections of a relay:

    python /opt/torutils/info.py --ctrlport 9051
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

*orstatus.py* collects closed cicuits event data:

    orstatus.py --ctrlport 9051

    DONE         6E642BD08A5D687B2C55E35936E3272636A90362  <snip>  9001 v4 0.3.5.11
    IOERROR      C89F338C54C21EDA9041DC8F070A13850358ED0B  <snip>   443 v4 0.4.3.5

### simple setup of an onion service
*websvc.sh*, *websvc.py*, *os.sh*

    ./os.sh; ./websvc.sh

should give you an onion service pointing to a local running simple HTTP server.
All files are created under */tmp*.
Verify it with

    tail -f /tmp/websvc.d/websvc.log /tmp/onionsvc.d/notice.log

and

    telnet 127.0.0.1 1234
    ...
    GET / HTTP/1.1

**Update:** look at https://github.com/micahflee/onionshare for a matured solution.

### fuzz testing of the Tor sources
Use the *american fuzzy lop* (https://github.com/google/AFL) in *fuzz.sh*

### more info
You need the Python lib Stem (https://stem.torproject.org/index.html) for the python scripts.

<a href="https://scan.coverity.com/projects/toralf-torutils">
  <img alt="Coverity Scan Build Status"
       src="https://scan.coverity.com/projects/21316/badge.svg"/>
</a>

