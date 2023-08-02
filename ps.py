#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
# -*- coding: utf-8 -*-


import argparse
import glob
import ipaddress
import os
import time

# https://github.com/torproject/stem.git
from stem.control import Controller, Listener
from stem.descriptor import parse_file
from stem.util.connection import get_connections, is_valid_ipv4_address, port_usage

"""
print out exit port statistics of a running Tor exit relay:

  port   # opened closed    max        (3.6 sec, lsof: 6068 conns in 0.9 sec)
  53   1    1    1    1    0    0  (DNS)
  80  1250   54   48   1250   54   48  (HTTP)
  81   1    0    0    1    0    0  (HTTP Alternate)
   110   1    0    0    1    0    0  (POP3)
"""


def parse_consensus(relays, filename):
    for desc in parse_file(filename):
        relays.setdefault(desc.address, []).append(desc.or_port)
        for address, port, is_ipv6 in desc.or_addresses:
            if is_ipv6:
                address = ipaddress.IPv6Address(address).exploded
            relays.setdefault(address, []).append(port)
    return relays


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-a", "--address", type=str, help="default: ::1", default="::1")
    parser.add_argument(
        "-c", "--ctrlport", type=int, help="default: 9051", default=9051
    )
    parser.add_argument("-r", "--resolver", help="default: autodetect", default="")
    parser.add_argument("-s", "--suffix", help="default: empty", default="")
    args = parser.parse_args()

    with Controller.from_port(address=args.address, port=args.ctrlport) as controller:
        controller.authenticate()

        try:
            ORPort = None
            ORPort6 = None

            for address, port in controller.get_listeners(Listener.OR):
                if is_valid_ipv4_address(address):
                    ORPort = port
                else:
                    ORPort6 = port

        except:
            print("Woops, control ports aren't configured")
            return

        relays = {}  # address => [orports...]
        relays = parse_consensus(
            relays, "/var/lib/tor/" + args.suffix + "/cached-consensus"
        )

        MaxOpened = {}  # hold the maximum amount of opened  ports
        MaxClosed = {}  # hold the maximum amount of closed  ports
        MaxAll = {}  # hold the maximum amount of overall ports

        Curr = {}  # the current network connections of Tor

        # avoid useless calculation of mean immediately after start
        #
        first = True

        while True:
            # read in all allowed exit ports
            #
            exit_ports = []
            for filename in glob.glob("/etc/tor/torrc.d/*") + (glob.glob("/etc/tor/*")):
                if os.path.isfile(filename):
                    inputfile = open(filename)
                    lines = inputfile.readlines()
                    inputfile.close()
                    for line in lines:
                        if line.startswith("ExitPolicy  *accept "):
                            accept = line.split()[2]
                            if ":" in accept:
                                port = accept.split(":")[1]
                                if "-" in port:
                                    min = port.split("-")[0]
                                    max = port.split("-")[1]
                                    for port in range(int(min), int(max)):
                                        exit_ports.append(port)
                                else:
                                    exit_ports.append(port)

            try:
                t1 = time.time()

                pid = controller.get_info("process/pid")
                connections = get_connections(
                    resolver=args.resolver, process_pid=pid, process_name="tor"
                )
                t2 = time.time()
                policy = controller.get_exit_policy()

                if not first:
                    Prev = Curr.copy()
                    Curr.clear()

                for conn in connections:
                    laddr, raddr = conn.local_address, conn.remote_address
                    lport, rport = conn.local_port, conn.remote_port

                    # ignore incoming connections
                    #
                    if conn.is_ipv6:
                        if lport == ORPort6:
                            if laddr == my_ipv6:
                                continue
                    else:
                        if lport == ORPort:
                            if laddr == my_ipv4:
                                continue

                    if raddr in relays:
                        if rport in relays[raddr]:
                            continue

                    if not policy.can_exit_to(raddr, rport):
                        continue

                    # store the connections itself instead just counting them here
                    # b/c we have to calculate the diff of 2 sets later too
                    #
                    Curr.setdefault(rport, []).append(str(lport) + ":" + raddr)

                dt = t2 - t1

                os.system("clear")
                print(
                    '  port   # opened closed    max        ( "%s" %s:%s, %i conns %.2f sec )'
                    % (args.resolver, args.address, args.ctrlport, len(connections), dt)
                )

                if first:
                    Prev = Curr.copy()

                ports = sorted(
                    set(list(Curr.keys()) + list(Prev.keys()) + list(MaxAll.keys()))
                )
                for port in ports:
                    c = set({})
                    p = set({})
                    if port in Prev:
                        p = set(Prev[port])
                    if port in Curr:
                        c = set(Curr[port])

                    n_curr = len(c)
                    n_opened = len(c - p)
                    n_closed = len(p - c)

                    MaxAll.setdefault(port, 0)
                    MaxOpened.setdefault(port, 0)
                    MaxClosed.setdefault(port, 0)

                    if not first:
                        if MaxAll[port] < n_curr:
                            MaxAll[port] = n_curr
                        if MaxOpened[port] < n_opened:
                            MaxOpened[port] = n_opened
                        if MaxClosed[port] < n_closed:
                            MaxClosed[port] = n_closed

                    stri = " %5i %5i %6i %6i   %6i %6i %6i  (%s)" % (
                        port,
                        n_curr,
                        n_opened,
                        n_closed,
                        MaxAll[port],
                        MaxOpened[port],
                        MaxClosed[port],
                        port_usage(port),
                    )
                    print(stri.replace(" 0", "  "))

                first = False

            except KeyboardInterrupt:
                break
            except Exception:
                continue


if __name__ == "__main__":
    # TODO: get this from torrc
    my_ipv4 = "65.21.94.13"
    my_ipv6 = ipaddress.IPv6Address("2a01:4f9:3b:468e::13").exploded
    main()
