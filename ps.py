#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
  # exit port stats of a running Tor relay, eg.:
  #
   port     # opened closed   /sec  2.9
     81     3      0      0   (HTTP Alternate)
    443  1733     43     33   (HTTPS)
    993    21      0      0   (IMAPS)
   5190     1      0      0   (AIM/ICQ)
   5222    61      0      0   (Jabber)
   5228    47      0      0   (Android Market)
   6667     3      0      0   (IRC)
   6697     1      0      0   (IRC)
   8082     3      0      0   (None)
   8333    12      0      0   (Bitcoin)
   9999     6      0      0   (distinct)
  19294     1      0      0   (Google Voice)
  50002    26      0      0   (Electrum Bitcoin SSL)
"""

import os
import time
from math import ceil
from stem.control import Controller
from stem.util.connection import get_connections, port_usage

def main():
  with Controller.from_port(port = 9051) as controller:

    def printOut (curr, prev, duration):
      os.system('clear')
      print ("   port     # opened closed   /sec  %.1f " % duration)

      ports = set(list(curr.keys()) + list(prev.keys()))

      for port in sorted(ports):
        if port in prev:
          p = set(prev[port])
        else:
          p = set({})
        if port in curr:
          c = set(curr[port])
        else:
          c = set({})

        print ("  %5i %5i %6i %6i   (%s)" % (port, len(c), ceil(len(c-p)/duration), ceil(len(p-c)/duration), port_usage(port)))

      return

    controller.authenticate()

    # for the runtime of this script we do assume no changes in relays[]
    #
    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    curr_time = time.time() - 1   # avoid dvision by a small number in the first round
    Curr = {}

    while True:
      try:
        prev_time, curr_time = curr_time, time.time()
        Prev, Curr = Curr, {}

        # be not faster than 1/sec
        #
        diff = curr_time - prev_time
        if diff < 1.0:
            time.sleep(1.0 - diff)
            curr_time = time.time()

        connections = get_connections('lsof', process_name='tor')
        policy = controller.get_exit_policy()

        for conn in connections:
          raddr, rport, lport = conn.remote_address, conn.remote_port, conn.local_port
          if raddr in relays:
            continue  # this speeds up from 8.5 sec to 2.5 sec
            if rport in relays[raddr]:
              continue  # this speeds up from 8.5 sec to 6.5 sec
          if policy.can_exit_to(raddr, rport):
            Curr.setdefault(rport, []).append(str(lport) + ':' + raddr)

        printOut (Curr, Prev, curr_time - prev_time)

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
