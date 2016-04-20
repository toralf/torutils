#!/usr/bin/env python
# -*- coding: utf-8 -*-

# exit port stats of a running Tor relay
#

import os
import time
from collections import Counter
from stem.control import Controller
from stem.util.connection import get_connections, system_resolvers, port_usage

def main():
  with Controller.from_port(port = 9051) as controller:

    def printOut (cur, old):
      "prints the current values and the diff"
      os.system('clear')
      print ("   port  count    +/- %s" % time.strftime("%c"))
      for port in sorted(cur.keys()):
        count = cur[port]
        if old[port]:
          diff = count - old[port]
        else:
          diff = count
        print ("  %5i  %5i %6i (%s)" % (port, count, diff, port_usage(port)))
      return

    controller.authenticate()
    relays = {}                                 # store here the tupel <ip address, ORport>
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)
    policy = controller.get_exit_policy()

    Cur = Counter()
    while True:
      try:
        connections = get_connections('lsof', process_name='tor')

        Old = Cur
        Cur = Counter()
        for conn in connections:
          if conn.protocol == 'udp':
            continue
          raddr = conn.remote_address
          if raddr in relays:
            continue
          rport = conn.remote_port
          if policy.can_exit_to(raddr, rport):
            Cur[rport] += 1;
        printOut (Cur, Old)

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
