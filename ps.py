#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
  # exit port stats of a running Tor relay, eg.:
  #
   port     # opened closed   2.1 sec
     81     8    0.0    0.0   (HTTP Alternate)
    443  1541   37.5   46.0   (HTTPS)
    587     2    0.0    0.0   (SMTP)
    993    11    0.0    0.0   (IMAPS)
   1863     1    0.0    0.0   (MSNP)
   2083     1    0.0    0.0   (radsec)
   5050     1    0.0    0.0   (Yahoo IM)
   5190     3    0.0    0.0   (AIM/ICQ)
   5222    27    0.0    0.0   (Jabber)
   5228    35    0.0    0.0   (Android Market)
   6667     4    0.0    0.0   (IRC)
   6697     2    0.0    0.0   (IRC)
   8082     5    0.0    0.0   (None)
   8333     9    0.0    0.0   (Bitcoin)
   8443     1    0.0    0.0   (PCsync HTTPS)
   9999     1    0.0    0.0   (distinct)
  50002    19    0.0    0.0   (Electrum Bitcoin SSL)
"""

import os
import time
from stem.control import Controller
from stem.util.connection import get_connections, port_usage

def main():
  with Controller.from_port(port = 9051) as controller:

    def printOut (curr, prev, duration):
      os.system('clear')
      print ("   port     # opened closed   %.1f sec" % duration)

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

        print ("  %5i %5i %6.1f %6.1f   (%s)" % (port, len(c), len(c-p)/duration, len(p-c)/duration, port_usage(port)))

      return

    controller.authenticate()

    # for the runtime of this script we do assume no changes in relays[]
    #
    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    curr_time = time.time()
    Curr = {}

    while True:
      try:
        connections = get_connections('lsof', process_name='tor')
        policy = controller.get_exit_policy()

        prev_time = curr_time
        curr_time = time.time()

        Prev = Curr
        Curr = {}

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
