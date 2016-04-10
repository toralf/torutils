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
    controller.authenticate()

    relays = {}    # store here the tupel <ip address, ORport>
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    class Port(Counter):
      def __str__(self):
        ret = ""
        for port in sorted(self.keys()):
          n = self[port]
          ret += "  %5i  %4i (%s)\n" % (port, n, port_usage(port))
        return ret.rstrip("\n")

    policy = controller.get_exit_policy()

    while True:
      try:
        connections = get_connections('lsof', process_name='tor')

        ports = Port()
        for conn in connections:
          if conn.protocol == 'udp':
            continue

          raddr = conn.remote_address
          if raddr in relays:
            continue

          rport = conn.remote_port
          if policy.can_exit_to(raddr, rport):
            ports[rport] += 1;

        os.system('clear')
        print ("   port count")
        print (ports)
        time.sleep(1)

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
