#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# collect data wrt to https://trac.torproject.org/projects/tor/ticket/13603
#

import argparse
import functools
import time

from stem import ORStatus
from stem.control import EventType, Controller
from stem.util.connection import is_valid_ipv4_address


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--ctrlport', help='default: 9051', default=9051)
  args = parser.parse_args()

  with Controller.from_port(port=int(args.ctrlport)) as controller:
    controller.authenticate()
    orconn_listener = functools.partial(orconn_event, controller)
    controller.add_event_listener(orconn_listener, EventType.ORCONN)

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
      print(' %15s %5i %s %s' % (desc.address, desc.or_port, ip, desc.version))
    else:
      print('')


if __name__ == '__main__':
  main()
