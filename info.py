#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
# -*- coding: utf-8 -*-

import argparse
import collections
import ipaddress
import sys
import time

from stem.connection import connect
from stem.control import Listener
from stem.descriptor import parse_file
from stem.util.connection import get_connections, port_usage

# https://github.com/torproject/stem.git
from stem.util.str_tools import short_time_label
from stem.util.system import start_time

HEADER_LINE = " {version}   uptime: {uptime}   flags: {flags}"

DIV = "+%s+%s+%s+" % ("-" * 30, "-" * 7, "-" * 7)
COLUMN = "| %-28s | %5s | %5s |"

INBOUND_OR_FROM_RELAY = "Inbound to OR from relay"
INBOUND_OR_FROM_NONRELAY = "Inbound to OR from non-relay"
INBOUND_CONTROLPORT = "Inbound to ControlPort"

OUTBOUND_RELAY_OR = "Outbound to relay OR"
OUTBOUND_RELAY_NONOR = "Outbound to relay non-OR"
OUTBOUND_AS_EXIT = "Outbound as Exit"
OUTBOUND_UNKNOWN = "Outbound unknown"


def i2str(i):
    return str(i) if i > 0 else " "


def parse_consensus(relays, filename):
    for desc in parse_file(filename):
        relays.setdefault(desc.address, []).append(desc.or_port)
        for address, port, is_ipv6 in desc.or_addresses:
            if is_ipv6:
                address = ipaddress.IPv6Address(address).exploded
            relays.setdefault(address, []).append(port)
    return relays


def main(args=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("-a", "--address", type=str, help="default: ::1", default="::1")
    parser.add_argument(
        "-c", "--ctrlport", type=int, help="default: 9051", default=9051
    )
    parser.add_argument("-r", "--resolver", help="default: autodetected", default="")
    parser.add_argument("-s", "--suffix", help="default: empty", default="")
    args = parser.parse_args()

    try:
        controller = connect(control_port=(args.address, args.ctrlport))
    except:
        print("Woops, controller connect failed")
        sys.exit(1)

    try:
        desc = controller.get_network_status(default=None)
    except:
        print("Woops, controller network status failed")
        sys.exit(1)

    pid = controller.get_pid()

    print(
        HEADER_LINE.format(
            version=str(controller.get_version()).split()[0],
            uptime=short_time_label(time.time() - start_time(pid)),
            flags=", ".join(desc.flags if desc else ["none"]),
        )
    )

    policy = controller.get_exit_policy()

    relays = {}  # address => [orports...]
    relays = parse_consensus(
        relays, "/var/lib/tor/data" + args.suffix + "/cached-consensus"
    )

    categories = collections.OrderedDict(
        (
            (INBOUND_OR_FROM_RELAY, []),
            (INBOUND_OR_FROM_NONRELAY, []),
            (INBOUND_CONTROLPORT, []),
            (OUTBOUND_RELAY_OR, []),
            (OUTBOUND_RELAY_NONOR, []),
            (OUTBOUND_AS_EXIT, []),
            (OUTBOUND_UNKNOWN, []),
        )
    )

    exit_connections = {}  # count connections per remote port
    port_or = controller.get_listeners(Listener.OR)[0][1]

    # classify connections
    try:
        for conn in get_connections(resolver=args.resolver, process_pid=pid):
            if conn.protocol == "udp":
                continue

            if conn.local_port == port_or:
                if conn.remote_address in relays:
                    categories[INBOUND_OR_FROM_RELAY].append(conn)
                else:
                    categories[INBOUND_OR_FROM_NONRELAY].append(conn)
            elif conn.local_port == args.ctrlport:
                categories[INBOUND_CONTROLPORT].append(conn)
            elif conn.remote_address in relays:
                if conn.remote_port in relays.get(conn.remote_address, []):
                    categories[OUTBOUND_RELAY_OR].append(conn)
                else:
                    categories[OUTBOUND_RELAY_NONOR].append(conn)
            elif policy.can_exit_to(conn.remote_address, conn.remote_port):
                categories[OUTBOUND_AS_EXIT].append(conn)
                exit_connections.setdefault(conn.remote_port, []).append(conn)
            else:
                categories[OUTBOUND_UNKNOWN].append(conn)
    except:
        print("Woops, get connections failed")
        sys.exit(1)

    # prettify statistic output
    print(DIV)
    print(COLUMN % ("Type", "IPv4", "IPv6"))
    print(DIV)

    total_ipv4, total_ipv6 = 0, 0

    for label, connections in categories.items():
        ipv4_count = len([conn for conn in connections if not conn.is_ipv6])
        ipv6_count = len(connections) - ipv4_count
        total_ipv4, total_ipv6 = total_ipv4 + ipv4_count, total_ipv6 + ipv6_count
        print(COLUMN % (label, i2str(ipv4_count), i2str(ipv6_count)))

    print(DIV)
    print(COLUMN % ("Total", i2str(total_ipv4), i2str(total_ipv6)))
    print(DIV)
    ipv4 = [
        conn.remote_address
        for conn in categories[INBOUND_OR_FROM_RELAY] + categories[OUTBOUND_RELAY_OR]
        if not conn.is_ipv6
    ]
    ipv6 = [
        conn.remote_address
        for conn in categories[INBOUND_OR_FROM_RELAY] + categories[OUTBOUND_RELAY_OR]
        if conn.is_ipv6
    ]
    print(" %-28s    %5i   %5i" % ("relay OR connections ", len(ipv4), len(ipv6)))
    print(
        " %-28s    %5i   %5i" % ("         unique ips", len(set(ipv4)), len(set(ipv6)))
    )

    # statistics for exit connections
    if exit_connections:
        print("")
        print(DIV)
        print(COLUMN % ("Exit Port", "IPv4", "IPv6"))
        print(DIV)

        total_ipv4, total_ipv6 = 0, 0

        for port in sorted(exit_connections):
            connections = exit_connections[port]
            ipv4_count = len([conn for conn in connections if not conn.is_ipv6])
            ipv6_count = len(connections) - ipv4_count
            total_ipv4 = total_ipv4 + ipv4_count
            total_ipv6 = total_ipv6 + ipv6_count

            # print description instead port number
            usage = port_usage(port)
            label = "%s (%s)" % (port, usage) if usage else port

            print(COLUMN % (label, i2str(ipv4_count), i2str(ipv6_count)))

        print(DIV)
        print(COLUMN % ("Total", total_ipv4, total_ipv6))
        print(DIV)

    # check for inbound DDoS
    ipv4 = {}
    ipv6 = {}
    for conn in categories[INBOUND_OR_FROM_NONRELAY]:
        address = conn.remote_address
        if conn.is_ipv6:
            address = ipaddress.IPv6Address(address).compressed
            ipv6.setdefault(address, []).append(conn.remote_port)
        else:
            ipv4.setdefault(address, []).append(conn.remote_port)

    limit = 8
    ddos4 = [address for address in ipv4 if len(ipv4[address]) > limit]
    ddos6 = [address for address in ipv6 if len(ipv6[address]) > limit]
    if ddos4:
        print("%5i inbound non-relay v4 with > %i connections" % (len(ddos4), limit))
        # print(sorted(ddos4))
    if ddos6:
        print("%5i inbound non-relay v6 with > %i connections" % (len(ddos6), limit))
        # print(sorted(ddos6))


if __name__ == "__main__":
    main()
