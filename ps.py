#!/usr/bin/env python
# -*- coding: utf-8 -*-


import getopt, os, sys, time
from math import ceil
from stem.control import Controller
from stem.util.connection import get_connections, port_usage, system_resolvers

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

    """
      print out exit port statistics of a running Tor exit relay:

      port     # opened closed      max    max    max  (2.7 sec, lsof: 13921 conns in 1.5 sec)
        53     6      3      1       10      4      4  (DNS)
        80  9170     83     69     9170   1906    104  (HTTP)
       143     4      0      0        4      0      0  (IMAP)
       443  1605     58     50     1708     58     87  (HTTPS)
    """
    def printOut (dt21, dt23, n):
      os.system('clear')
      print ("  port     # opened closed      max    max    max  (%.1f sec, %s: %i conns in %.1f sec) " % (dt23, netresolver, n, dt21))

      ports = set(list(Curr.keys()) + list(Prev.keys()) + list(BurstAll.keys()))

      # calculate the mean just for values above 1 second
      #
      if dt23 < 1.0:
        dt = 1.0
      else:
        dt = dt23

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

        if BurstAll[port] < n_curr:
          BurstAll[port] = n_curr
        if BurstOpened[port] < n_opened:
          BurstOpened[port] = n_opened
        if BurstClosed[port] < n_closed:
          BurstClosed[port] = n_closed

        print (" %5i %5i %6i %6i   %6i %6i %6i  (%s)" % (port, n_curr, n_opened, n_closed, BurstAll[port], BurstOpened[port], BurstClosed[port], port_usage(port)))
      return

    #
    #
    controller.authenticate()

    # for the runtime of this script we do assume to have no significant
    # changes in relays or exit policy, therefore get it outside of the loop
    #
    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)
    policy = controller.get_exit_policy()

    BurstOpened = {}  # catch the maximum of opened  ports
    BurstClosed = {}  # catch the maximum of closed  ports
    BurstAll    = {}  # catch the maximum of overall ports

    Curr = {}   # the current opened exit connections
    first = 1   # flag to avoid calcualtion a wrong mean value during start

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

          # b/c can_exit_to() is slow we don't consider the case of an remote relay
          # offering a web service beside Tor and therefore is the target of an exit connection
          #
          if raddr in relays:
            continue

          # we define an unique connection as a <remote port, local port + ":" + remote address> pair
          # we need to store the connections itself here and do not only count them here
          # to calculate the correct difference of 2 Dicts in printOut()
          #
          if policy.can_exit_to(raddr, rport):
            Curr.setdefault(rport, []).append(str(lport)+':'+raddr)

        t3 = time.time()

        # avoid wrong calculation of the mean of closed and opened ports in printOut()
        #
        if first == 1:
          first = 0
          Prev = Curr.copy()

        printOut (t2-t1, t3-t2, len(connections))

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
