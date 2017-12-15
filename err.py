#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# collect data wrt to https://trac.torproject.org/projects/tor/ticket/13603
#

import time
import functools
import argparse

from stem import ORStatus, ORClosureReason
from stem.control import EventType, Controller
from stem.util.connection import is_valid_ipv6_address

def main():
  ctrlport = 9051

  parser = argparse.ArgumentParser()
  parser.add_argument("--ctrlport", help="default: " + str(ctrlport))

  args = parser.parse_args()

  if args.ctrlport:
    ctrlport = int(args.ctrlport)

  class Cnt:
    def __init__(self, done=0, closed=0, ioerror=0):
      self.done     = done
      self.closed   = closed
      self.ioerror  = ioerror

  c = Cnt()

  with Controller.from_port(port=ctrlport) as controller:
    controller.authenticate()

    orconn_listener = functools.partial(orconn_event, controller, c)
    controller.add_event_listener(orconn_listener, EventType.ORCONN)

    while True:
      try:
        time.sleep(1)
      except KeyboardInterrupt:
        break

def orconn_event(controller, c, event):
  if event.status == ORStatus.CLOSED:

    fingerprint = event.endpoint_fingerprint
    print ("%i %-15s %s" % (event.arrived_at, event.reason, fingerprint), end='')
    relay = controller.get_network_status(fingerprint, None)
    if (relay):
      if is_valid_ipv6_address(relay.address):
        ip = 'v6'
      else:
        ip = 'v4'
      print (" %17s  %5i  %s  %s  %s" % (relay.address, relay.or_port, ip, controller.get_info("ip-to-country/%s" % relay.address, 'unknown'), relay.nickname))
    else:
      print ('', flush=True)

if __name__ == '__main__':
  main()
