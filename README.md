[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) are designed
to react on DDoS network attack against a Tor relay
(issues [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)).
They do block ips making too much connection (attempts) to the local ORPort.
Both [this](./metrics-1.svg) and [this](./metrics-2.svg) metric show the effect.
The data were gathered by [sysstat](http://pagesperso-orange.fr/sebastien.godard/).

### Quick start
The packages [iptables](https://www.netfilter.org/projects/iptables/) and [jq](https://stedolan.github.io/jq/) are needed.
The call below replaces the content of the [filter](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) table of _iptables_ with the [rule set](#rule-set) described below.

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

Best is to (re-)start Tor afterwards.
The live statistics of your network rules can be shown by:

```bash
sudo watch -t ./ipv4-rules.sh
```

The output should look similar to these [IPv4](./iptables-L.txt) and [IPv6](./ip6tables-L.txt) examples.
To reset the filter table, run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule set
The rules for an ip connecting to the local ORPort are:

1. trust Tor authorities and snowflake
2. block the ip for 30 min if > 5 inbound connection attempts per minute are made
3. block the ip for 30 min if > 3 inbound connections are established
4. ignore any further connection attempt if the ip is hosting only 1 relay and has already 1 inbound connection established
5. ignore any further connection attempt if 2 inbound connections are already established

### Installation and configuration hints
The instructions are made for the IPv4 script. The IPv6 script can be handled in a similar way.

If the parsing of the torrc (line [145](ipv4-rules.sh#L145)) doesn't work, then:
1. specify the relays in the environment, eg.:
    ```bash
    export CONFIGURED_RELAYS="1.2.3.4:443"
    export CONFIGURED_RELAYS6="[cafe::beef]:9001"
    ```
1. -and/or- create a pull requests to fix the script ;)

Allow inbound traffic to additional local network services by:
1. specifying them in the environment, eg.:
    ```bash
    export ADD_LOCAL_SERVICES="1.2.3.4:80 1.2.3.4:993"
    export ADD_LOCAL_SERVICES6="[dead:beef]:25"
    ```
1. -or- hard code them in line [88](ipv4-rules.sh#L88)
1. -or- edit the default policy in line [6](ipv4-rules.sh#L6) to accept any TCP inbound traffic not matching an iptables rule:
    ```bash
    iptables -P INPUT ACCEPT
    ```

If you do not use Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/), then
1. remove the _addHetzner()_ code, at least that call in line [172](ipv4-rules.sh#L172)
1. -or- just ignore it

I do have set the _uname_ limit for the Tor process to _60000_.
Furthermore I do apply this sysctl settings via _/etc/sysctl.d/local.conf_:

```console
net.ipv4.ip_local_port_range = 2000 63999
kernel.kptr_restrict = 1
kernel.perf_event_paranoid = 3
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
user.max_user_namespaces = 0
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
```

## query Tor via its API

[info.py](./info.py) gives a summary of all  connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gives here:

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

For a monitoring of _exit_ connections use [ps.py](./ps.py):

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

### Prerequisites
An open Tor control port is needed to query the Tor process via API.
Configure it in _torrc_, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The [Stem](https://stem.torproject.org/index.html) python library is mandatory.
The latest version can be derived by eg.:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

## Misc

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to a local ORPort than the given upper limit (default: 2).
It should usually list _snowflake-01_ only:

```console
ip                       193.187.88.42           12
relay:65.21.94.13:443            ips:1     conns:12
```

The script [ipset-stats.sh](./ipset-stats.sh) (package [gnuplot](http://www.gnuplot.info/) is needed)
dumps and visualizes the content of an [ipset](https://ipset.netfilter.org).
The cron example below (of user _root_) shows how to gather data:

```cron
# Tor DDoS stats
*/30 * * * *  d=$(date +\%H-\%M); ~/torutils/ipset-stats.sh -d | tee -a /tmp/ipset4.txt > /tmp/ipset4.$d.txt
```

from which histograms can be plotted, eg.:

```bash
sudo ./ipset-stats.sh -p /tmp/ipset4.*.txt
```

which gives currently
```console
                       49397 hits of 6565 ips
       +-----------------------------------------------------+
       |o   +     +    +     +    +    +     +    +     +    |
  1024 |-+  oo                                             +-|
       |   o   o                                             |
       | oo                                                  |
   256 |-+      o                    o                     +-|
       |         o                    o                      |
       |                                                     |
    64 |-+                                                 o-|
       |          o                    o                     |
       |                                                     |
       |           o o              o                     o  |
    16 |-+          o o           oo                       +-|
       |               oo o  o   o      o   o   o        o   |
       |                 o      o          o  o      o       |
     4 |-+                  o  o          o    o  o     o  +-|
       |    +     +    +     +o   +    +     o    + o  o+    |
       +-----------------------------------------o-o---------+
       0    5     10   15    20   25   30    35   40    45   50
                                 hit
```

To check, how often Tor relays were blocked, run:

```bash
curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - | jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | xargs -n 1 | sort -u > /tmp/relays
grep -h -w -f /tmp/relays /tmp/ipset4.*.txt | sort | uniq -c | sort -bn
```

[orstatus.py](./orstatus.py) logs the reason of Tor circuit closing events.
[orstatus-stats.sh](./orstatus-stats.sh) prints and/or plots statistics from the output, eg.:

```bash
sudo ./orstatus.py --ctrlport 9051 --address ::1 >> /tmp/orstatus.9051 &
```

After running it for a while evaluate the output with (specifying the reason is optional):

```bash
sudo ./orstatus-stats.sh /tmp/orstatus.9051 CONNECTRESET
```

If you do use [Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/)
then [key-expires.py](./key-expires.py) helps you to not miss the key rotation timeline.
It returns the seconds before the mid-term signing key expires, a cron job like:

```cron
# Tor expiring keys
@daily      n="$(( $(/opt/torutils/key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)/86400 ))"; [[ $n -lt 23 ]] && echo "Tor signing key expires in less than $n day(s)"
```

helps with that (if a mailer is configured).
