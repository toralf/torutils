#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# collect data wrt to https://trac.torproject.org/projects/tor/ticket/13603
#

import time
import functools
import argparse

from stem import ORStatus, ORClosureReason
from stem.control import EventType, Controller

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
    c.closed += 1

    if event.reason == ORClosureReason.DONE:
      c.done += 1

    elif event.reason == ORClosureReason.IOERROR:
      c.ioerror += 1

      fingerprint = event.endpoint_fingerprint
      print (" %5i %5i %5i  %i %s %40s" % (c.closed, c.done, c.ioerror, event.arrived_at, time.ctime(event.arrived_at), fingerprint), end='')
      relay = controller.get_network_status(fingerprint, None)
      if (relay):
        print (" %15s %5i %s %s" % (relay.address, relay.or_port, controller.get_info("ip-to-country/%s" % relay.address, 'unknown'), relay.nickname))
      else:
        print ('', flush=True)

if __name__ == '__main__':
  main()
