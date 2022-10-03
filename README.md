[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# torutils
Few tools for a Tor relay.

## block DDoS traffic

### rule set
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

### start/stop
The IPv4 and IPv6 rules are started separately:
```bash
sudo ./ipv4-rules.sh start
sudo ./ipv6-rules.sh start
```
After this Tor should be (re)started.

Replace `start` with `stop` to remove the rules. This requires no restart of Tor.
### monitoring
The current settings of your firewall can be seen via:
```bash
sudo iptables -nv -L -t raw
sudo iptables -nv -L -t filter
```
The script _ipset-stats.sh_ dumps and visualizes ipset data (default: blocked ips).
Run it in regular intervalls and plot the results, eg. for 3 hours:
```bash
for i in 1 2 3 4 5 6
do
  sudo ./ipset-stats.sh -d > /tmp/ipset4.$i.txt
  sudo ./ipset-stats.sh -D > /tmp/ipset6.$i.txt
  sleep 1800
done
sudo ./ipset-stats.sh -p /tmp/ipset4.?.txt
sudo ./ipset-stats.sh -p /tmp/ipset6.?.txt
```
### configuring
You have to configure your relay(s) explicitely, eg. for IPv4 change line [122](ipv4-rules.sh#L122) of `ipv4-rules.sh`:
```bash
relays="<ip address>:<or port>"
```
Furthermore comment out the function calls `addMisc` (and mayy `addHetzner` too) few lines below -or- remove the not-used code lines entirely.
For installation prerequisites please take a look at [Installation](#Installation).

## query Tor process via its API
A configured control port in `torrc` is needed for the python tools to work, eg.:
```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```
_info.py_ gives a summary of a Tor relay:
```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```
```console
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
```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```
```console
    port     # opened closed      max                ( "" ::1:9051, 8998 conns 0.28 sec )
     853     3                      3      1      1  (None)
    5222    42                     42                (Jabber)
    5223     4                      4                (Jabber)
    5269     2                      2                (Jabber)
    6667     4                      4                (IRC)
    7777     3                      3                (None)
```
_orstatus.py_ logs the reasons of circuit closing events, _orstatus-stats.sh_ made stats of its output.
Run it in a terminal, (set _PYTHONPATH_ before) eg.:
```bash
sudo ./orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus.9051
```
after a certain time press Ctrl-C and take a look, eg. at the distribution of _IOERROR_:
```bash
sudo ./orstatus-stats.sh /tmp/orstatus.9051
```
_key-expires.py_ returns the time in seconds when the mid-term signing key will expire, eg.:
```bash
sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert
7286915

expr 7286915 / 86400
84
```

## Installation
You might have to install [iptables](https://www.netfilter.org/projects/iptables/) (which should install [ipset](https://ipset.netfilter.org) too), eg.:
```bash
sudo apt-get install iptables 
```
for Debian installer systems.
[jq](https://stedolan.github.io/jq/) is used too in _ipvX-rules.sh_ and is usually available by your package manager.
The [Stem](https://stem.torproject.org/index.html) library (for the python scripts) however might have been installed manually:
```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```
[gnuplot](http://www.gnuplot.info/) is used by the  _*-stats.sh_ scripts.
