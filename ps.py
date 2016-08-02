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
      print out exit port stats of a running Tor relay eg.:

       port     # opened closed   / 2.3sec    (get_conn=0.9 sec)
         53     3      2      1   (DNS)
         81     2      0      0   (HTTP Alternate)
         88     5      1      0   (Kerberos)
        443  2285     75     86   (HTTPS)
        587     1      0      0   (SMTP)
        706     1      0      0   (SILC)
        993    20      0      0   (IMAPS)
        995     1      0      0   (POP3S)
       2096     1      1      0   (NBX DIR)
       5050     1      0      0   (Yahoo IM)
       5222    32      0      0   (Jabber)
       5228    46      0      0   (Android Market)
       6667     2      0      0   (IRC)
       6697     2      0      0   (IRC)
       8000     1      0      0   (iRDMI)
       8082     2      0      0   (None)
       8087     2      0      0   (SPP)
       8333    14      0      0   (Bitcoin)
       8443     1      0      0   (PCsync HTTPS)
      50002    12      0      0   (Electrum Bitcoin SSL)
    """
    def printOut (curr, prev, dt12, dt23, n, resolver):
      os.system('clear')
      print ("   port     # opened closed   / %.1fsec    (%s: %i conns in %.1f sec) " % (dt23, resolver, n, dt12))

      ports = set(list(curr.keys()) + list(prev.keys()))

      if dt23<1.0:
        dt=1.0
      else:
        dt=dt23

      for port in sorted(ports):
        if port in prev:
          p = set(prev[port])
        else:
          p = set({})
        if port in curr:
          c = set(curr[port])
        else:
          c = set({})

        n_curr = len(c)
        n_opened = ceil(len(c-p)/dt)
        n_closed = ceil(len(p-c)/dt)

        print ("  %5i %5i %6i %6i   (%s)" % (port, n_curr, n_opened, n_closed, port_usage(port)))
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

    Curr = {}
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

          # b/c can_exit_to() is slooow we do ignore the case of an relay
          # being an exit too to spped up the loop
          #
          if rport == 0:
            continue  # happens for 'proc' as resolver
          if raddr in relays:
            continue

          # a unique connection is a <remote port, local port + ":" + remote address> tupel
          #
          if policy.can_exit_to(raddr, rport):
            Curr.setdefault(rport, []).append(str(lport)+':'+raddr)

        t3 = time.time()
        if first == 1:
          first = 0
          Prev = Curr.copy()

        printOut (Curr, Prev, t2-t1, t3-t2, len(connections), netresolver)

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
