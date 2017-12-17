#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# collect data wrt to https://trac.torproject.org/projects/tor/ticket/13603
#

import time
import functools
import argparse

from stem import ORStatus, ORClosureReason
from stem.control import EventType, Controller
from stem.util.connection import is_valid_ipv4_address

def main():
  ctrlport = 9051

  parser = argparse.ArgumentParser()
  parser.add_argument("--ctrlport", help="default: " + str(ctrlport))

  args = parser.parse_args()

  if args.ctrlport:
    ctrlport = int(args.ctrlport)

  relays = {}

  with Controller.from_port(port=ctrlport) as controller:
    controller.authenticate()

    orconn_listener = functools.partial(orconn_event, controller, relays)
    controller.add_event_listener(orconn_listener, EventType.ORCONN)

    while True:
      try:
        time.sleep(1)
      except KeyboardInterrupt:
        break

def orconn_event(controller, relays, event):
  if event.status == ORStatus.CLOSED:

    fingerprint = event.endpoint_fingerprint

    print ("%-12s %s" % (event.reason, fingerprint), end='')

    relay = controller.get_network_status(fingerprint, None)
    if (relay):
      if is_valid_ipv4_address(relay.address):
        ip = 'v4'
      else:
        ip = 'v6'
      print (" %15s %5i %s" % (relay.address, relay.or_port, ip))
    else:
      print ('', flush=True)

if __name__ == '__main__':
  main()
