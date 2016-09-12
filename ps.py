#!/usr/bin/env python
# -*- coding: utf-8 -*-


import getopt, os, sys, time
from math import ceil
from stem.control import Controller
from stem.util.connection import get_connections, port_usage, system_resolvers

"""
  print out exit port statistics of a running Tor exit relay:

  port     # opened closed      max                (3.6 sec, lsof: 6068 conns in 0.9 sec)
    53     1      1      1        1      0      0  (DNS)
    80  1250     54     48     1250     54     48  (HTTP)
    81     1      0      0        1      0      0  (HTTP Alternate)
   110     1      0      0        1      0      0  (POP3)
"""


def main():
  try:
    opts, args = getopt.getopt(sys.argv[1:], "p:r:", ["ctrlport=", "resolver="])
  except getopt.GetoptError as err:
    print(err)
    sys.exit(2)

  ctrlport = 9051
  netresolver = 'lsof'

  for opt, val in opts:
    if opt in ("-h", "--help"):
      print ("help help help")
      sys.exit()
    elif opt in ('-p', '--ctrlport'):
      ctrlport = val
    elif opt in ('-r', '--resolver'):
      # print ("available system resolvers are %s" % system_resolvers()) : ['proc', 'netstat', 'lsof', 'ss']
      netresolver = val

  with Controller.from_port(port = ctrlport) as controller:
    print ("authenticating ...")
    controller.authenticate()

    # assume to have no changes in relays or exit policy during runtime of this script
    #
    print ("get relays ...")
    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)
    policy = controller.get_exit_policy()

    BurstOpened = {}  # hold the maximum amount of opened  ports
    BurstClosed = {}  # hold the maximum amount of closed  ports
    BurstAll    = {}  # hold the maximum amount of overall ports

    Curr = {}   # the current network connections of Tor

    print ("starting ...")
    first = 1
    while True:
      try:
        Prev = Curr.copy()
        Curr.clear()

        t1 = time.time()
        connections = get_connections(resolver=netresolver, process_name='tor')

        t2 = time.time()
        for conn in connections:
          raddr, rport, lport = conn.remote_address, conn.remote_port, conn.local_port

          if rport == 0:    # happens for 'proc' as resolver
            continue

          # b/c can_exit_to() is slow we ignore the case that a relay offers an exit service too
          #
          if raddr in relays:
            continue

          # we need to store the connections itself here and can't just count them here
          # b/c we have to calculate a diff of both sets later
          #
          if policy.can_exit_to(raddr, rport):
            Curr.setdefault(rport, []).append(str(lport)+':'+raddr)

        t3 = time.time()

        # avoid ueseless calculation of mean immediately after start
        #
        if first == 1:
          Prev = Curr.copy()

        dt23 = t3-t2
        dt21 = t2-t1
        # calculate the mean only for values greater 1 sec
        #
        if dt23 < 1.0:
          dt = 1.0
        else:
          dt = dt23

        os.system('clear')
        print ("  port     # opened closed      max                (%.1f sec, %s: %i conns in %.1f sec) " % (dt23, netresolver, len(connections), dt21))
        lines = 0;
        ports = set(list(Curr.keys()) + list(Prev.keys()) + list(BurstAll.keys()))
        for port in sorted(ports):
          if port in Prev:
            p = set(Prev[port])
          else:
            p = set({})
          if port in Curr:
            c = set(Curr[port])
          else:
            c = set({})

          n_curr = len(c)
          n_opened = ceil(len(c-p)/dt)
          n_closed = ceil(len(p-c)/dt)

          BurstAll.setdefault(port, 0)
          BurstOpened.setdefault(port, 0)
          BurstClosed.setdefault(port, 0)

          if first == 0:
            if BurstAll[port] < n_curr:
              BurstAll[port]    = n_curr
              BurstOpened[port] = n_opened
              BurstClosed[port] = n_closed

          print (" %5i %5i %6i %6i   %6i %6i %6i  (%s)" % (port, n_curr, n_opened, n_closed, BurstAll[port], BurstOpened[port], BurstClosed[port], port_usage(port)))

          lines += 1
          if lines % 6 == 0:
            print("")

        first = 0

      except KeyboardInterrupt:
        break


if __name__ == '__main__':
  main()
