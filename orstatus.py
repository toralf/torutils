#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# -*- coding: utf-8 -*-

# dump OR closing event reasons:
#
#   orstatus.py --address 127.0.0.1 --ctrlport 39051

import argparse
import functools
import time

# https://github.com/torproject/stem.git
from stem import ORStatus
from stem.control import Controller, EventType
from stem.descriptor import parse_file
from stem.util.connection import is_valid_ipv4_address


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-a", "--address", type=str, help="default: 127.0.0.1", default="127.0.0.1"
    )
    parser.add_argument(
        "-c", "--ctrlport", type=int, help="default: 9051", default=9051
    )
    parser.add_argument("-s", "--suffix", help="default: empty", default="")
    args = parser.parse_args()

    with Controller.from_port(address=args.address, port=args.ctrlport) as controller:
        controller.authenticate()

        for desc in parse_file("/var/lib/tor/" + args.suffix + "/cached-consensus"):
            ip = "v4" if is_valid_ipv4_address(desc.address) else "v6"
            desc_versions[desc.fingerprint] = [
                desc.address,
                desc.or_port,
                ip,
                desc.version,
            ]

        orconn_listener = functools.partial(orconn_event, controller)
        controller.add_event_listener(orconn_listener, EventType.ORCONN)
        while True:
            try:
                time.sleep(1)
            except KeyboardInterrupt:
                break


def orconn_event(controller, event):
    if event.status == ORStatus.CLOSED:
        fingerprint = event.endpoint_fingerprint
        if fingerprint:
            print("%i %-12s %s" % (time.time(), event.reason, fingerprint), end="")
            if fingerprint in desc_versions:
                address, or_port, ip_version, tor_version = desc_versions[fingerprint]
                print(
                    " %-15s %5i %s %s" % (address, or_port, ip_version, tor_version),
                    flush=True,
                )
            else:
                print("", flush=True)


if __name__ == "__main__":
    desc_versions = {}
    main()
