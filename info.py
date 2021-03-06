#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
import collections
import time
import ipaddress

from stem.util.str_tools import short_time_label
from stem.util.system import start_time

from stem.connection import connect
from stem.control import Listener
from stem.descriptor import parse_file
from stem.util.connection import get_connections, port_usage

HEADER_LINE = ' {version}   uptime: {uptime}   flags: {flags}\n'

DIV = '+%s+%s+%s+' % ('-' * 30, '-' * 6, '-' * 6)
COLUMN = '| %-28s | %4s | %4s |'

INBOUND_ORPORT = 'Inbound to our OR from OR'
INBOUND_ORPORT_OTHER = 'Inbound to our OR from other'
INBOUND_DIRPORT = 'Inbound to our DirPort'
INBOUND_CONTROLPORT = 'Inbound to our ControlPort'

OUTBOUND_ORPORT = 'Outbound to relay OR'
OUTBOUND_ANOTHER = 'Outbound to relay non-OR'
OUTBOUND_EXIT = 'Outbound exit traffic'
OUTBOUND_UNKNOWN = 'Outbound unknown'


def i2str(i):
    return str(i) if i > 0 else ' '


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
    parser.add_argument('--ctrlport', type=int, help='default: 9051', default=9051)
    parser.add_argument('--resolver', help='default: autodetected', default='')
    args = parser.parse_args()

    controller = connect(control_port=('127.0.0.1', args.ctrlport))
    if not controller:
        return

    desc = controller.get_network_status(default=None)
    pid = controller.get_pid()

    print(HEADER_LINE.format(
        version=str(controller.get_version()).split()[0],
        uptime=short_time_label(time.time() - start_time(pid)),
        flags=', '.join(desc.flags if desc else ['none']),
    ))

    policy = controller.get_exit_policy()
    relays = {}    # address => [orports...]
    relays = parse_consensus(relays, '/var/lib/tor/data/cached-consensus')
    relays = parse_consensus(relays, '/var/lib/tor/data2/cached-consensus')

    # categorize our connections

    categories = collections.OrderedDict((
        (INBOUND_ORPORT, []),
        (INBOUND_ORPORT_OTHER, []),
        (INBOUND_DIRPORT, []),
        (INBOUND_CONTROLPORT, []),
        (OUTBOUND_ORPORT, []),
        (OUTBOUND_ANOTHER, []),
        (OUTBOUND_EXIT, []),
        (OUTBOUND_UNKNOWN, []),
    ))

    exit_connections = {}                             # port => [connections]
    port_or = controller.get_listeners(Listener.OR)[0][1]
    port_dir = controller.get_listeners(Listener.DIR)[0][1]

    for conn in get_connections(resolver=args.resolver, process_pid=pid):
        if conn.protocol == 'udp':
            continue

        if conn.local_port == port_or:
            if conn.remote_address in relays:
                categories[INBOUND_ORPORT].append(conn)
            else:
                categories[INBOUND_ORPORT_OTHER].append(conn)
        elif conn.local_port == port_dir:
            categories[INBOUND_DIRPORT].append(conn)
        elif conn.local_port == args.ctrlport:
            categories[INBOUND_CONTROLPORT].append(conn)
        elif conn.remote_address in relays:
            if conn.remote_port in relays.get(conn.remote_address, []):
                categories[OUTBOUND_ORPORT].append(conn)
            else:
                categories[OUTBOUND_ANOTHER].append(conn)
        elif policy.can_exit_to(conn.remote_address, conn.remote_port):
            categories[OUTBOUND_EXIT].append(conn)
            exit_connections.setdefault(conn.remote_port, []).append(conn)
        else:
            categories[OUTBOUND_UNKNOWN].append(conn)

    print(DIV)
    print(COLUMN % ('Type', 'IPv4', 'IPv6'))
    print(DIV)

    total_ipv4, total_ipv6 = 0, 0

    for label, connections in categories.items():
        ipv4_count = len([conn for conn in connections if not conn.is_ipv6])
        ipv6_count = len(connections) - ipv4_count
        total_ipv4, total_ipv6 = total_ipv4 + ipv4_count, total_ipv6 + ipv6_count
        print(COLUMN % (label, i2str(ipv4_count), i2str(ipv6_count)))

    print(DIV)
    print(COLUMN % ('Total', i2str(total_ipv4), i2str(total_ipv6)))
    print(DIV)
    print('')

    if exit_connections:
        print(DIV)
        print(COLUMN % ('Exit Port', 'IPv4', 'IPv6'))
        print(DIV)

        total_ipv4, total_ipv6 = 0, 0

        for port in sorted(exit_connections):
            connections = exit_connections[port]
            ipv4_count = len([conn for conn in connections if not conn.is_ipv6])
            ipv6_count = len(connections) - ipv4_count
            total_ipv4 = total_ipv4 + ipv4_count
            total_ipv6 = total_ipv6 + ipv6_count

            usage = port_usage(port)
            label = '%s (%s)' % (port, usage) if usage else port

            print(COLUMN % (label, i2str(ipv4_count), i2str(ipv6_count)))

        print(DIV)
        print(COLUMN % ('Total', total_ipv4, total_ipv6))
        print(DIV)


if __name__ == '__main__':
    main()
