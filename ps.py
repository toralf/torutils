#!/usr/bin/env python
# -*- coding: utf-8 -*-

# exit port stats of a running Tor relay
#
#eg.:
#
   #port   cur   old opened closed   Thu Apr 21 15:56:52 2016
     #81     4     4      0      0   (HTTP Alternate)
     #88     1     1      0      0   (Kerberos)
    #443   491   490     13     12   (HTTPS)
    #993     6     6      0      0   (IMAPS)
   #1500     2     2      0      0   (NetGuard)
   #3128     1     1      0      0   (SQUID)
   #3389     1     1      0      0   (WBT)
   #5222    21    21      0      0   (Jabber)
   #5228    10    10      0      0   (Android Market)
   #6667     4     4      0      0   (IRC)
   #8082     4     4      0      0   (None)
   #8333     4     4      0      0   (Bitcoin)
   #8888     1     1      0      0   (NewsEDGE)
   #9999     5     5      0      0   (distinct)
  #50002    15    15      0      0   (Electrum Bitcoin SSL)

import os
import time
from collections import Counter
from stem.control import Controller
from stem.util.connection import get_connections, system_resolvers, port_usage

def main():
  with Controller.from_port(port = 9051) as controller:

    def printOut (cur, old):
      os.system('clear')
      print ("   port   cur   old opened closed   %s" % time.strftime("%c"))
      for port in sorted(cur.keys()):
        n = set(cur[port])
        if port in old:
          o = set(old[port])
        else:
          o = set({})
        opened = n - o
        closed = o - n
        print ("  %5i %5i %5i %6i %6i   (%s)" % (port, len(n), len(o), len(opened), len(closed), port_usage(port)))

      return

    controller.authenticate()

    relays = {}                                 # store here the tupel <ip address, ORport>
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    policy = controller.get_exit_policy()

    Cur = {}
    while True:
      try:
        connections = get_connections('lsof', process_name='tor')

        Old = Cur.copy()
        Cur.clear()
        for conn in connections:
          if conn.protocol == 'udp':
            continue
          raddr = conn.remote_address
          if raddr in relays:
            continue
          rport = conn.remote_port
          if policy.can_exit_to(raddr, rport):
            Cur.setdefault(rport, []).append(raddr)
            #Cur.setdefault(rport, {}).add(raddr)

        printOut (Cur, Old)

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
