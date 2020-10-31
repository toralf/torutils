#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# collect data wrt to https://trac.torproject.org/projects/tor/ticket/13603
#

import argparse
import functools
import time

from stem import ORStatus
from stem.control import EventType, Controller
from stem.descriptor import parse_file
from stem.util.connection import is_valid_ipv4_address


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--ctrlport', type=int, help='default: 9051', default=9051)
  args = parser.parse_args()

  with Controller.from_port(port=args.ctrlport) as controller:
    controller.authenticate()
    orconn_listener = functools.partial(orconn_event, controller)
    controller.add_event_listener(orconn_listener, EventType.ORCONN)

    for desc in parse_file('/var/lib/tor/data/cached-consensus'):
      desc_versions[desc.fingerprint] = desc.version

    while True:
      try:
        time.sleep(1)
      except KeyboardInterrupt:
        break


async def orconn_event(controller, event):
  if event.status == ORStatus.CLOSED:
    fingerprint = event.endpoint_fingerprint
    desc = await controller.get_network_status(fingerprint, None)

    print ('%-12s %s' % (event.reason, fingerprint), end='')
    if (desc):
      ip = 'v4' if is_valid_ipv4_address(desc.address) else 'v6'
      version = desc.version
      if not version:
        version = desc_versions[fingerprint] if fingerprint in desc_versions else 'n/a'
      print(' %15s %5i %s %s' % (desc.address, desc.or_port, ip, version))
    else:
      print('')


if __name__ == '__main__':
  desc_versions = {}
  main()
