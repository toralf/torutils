#!/usr/bin/env python3
# -*- coding: utf-8 -*-


import argparse, os, sys, time, glob
from math import ceil
from stem.control import Controller, Listener
from stem.util.connection import get_connections, port_usage, system_resolvers, is_valid_ipv4_address

"""
  print out exit port statistics of a running Tor exit relay:

  port     # opened closed      max                (3.6 sec, lsof: 6068 conns in 0.9 sec)
    53     1      1      1        1      0      0  (DNS)
    80  1250     54     48     1250     54     48  (HTTP)
    81     1      0      0        1      0      0  (HTTP Alternate)
   110     1      0      0        1      0      0  (POP3)
"""


def main():
  ctrlport = 9051
  resolver = 'proc'

  parser = argparse.ArgumentParser()
  parser.add_argument("--ctrlport", help="default: " + str(ctrlport))
  parser.add_argument("--resolver", help="default: " + resolver)
  args = parser.parse_args()

  if args.ctrlport:
    ctrlport = int(args.ctrlport)

  if args.resolver:
    resolver= str(args.resolver)

  with Controller.from_port(port=ctrlport) as controller:
    controller.authenticate()

    try:
      ControlPort = int(controller.get_conf("ControlPort"))
      ORPort   = None
      ORPort6  = None
      DirPort  = None
      DirPort6 = None

      for address, port in controller.get_listeners(Listener.OR):
        if is_valid_ipv4_address(address):
          ORPort = port
        else:
          ORPort6 = port

      for address, port in controller.get_listeners(Listener.DIR):
        if is_valid_ipv4_address(address):
          DirPort = port
        else:
          DirPort6 = port

    except Exception as Exc:
      print ("Woops, control ports aren't configured")
      print (Exc)
      return

    # we will ignore changes of relays during the runtime of this script
    #
    relays = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    MaxOpened = {}  # hold the maximum amount of opened  ports
    MaxClosed = {}  # hold the maximum amount of closed  ports
    MaxAll    = {}  # hold the maximum amount of overall ports

    Curr = {}   # the current network connections of Tor

    # avoid useless calculation of mean immediately after start
    #
    first = 1

    while True:
      # read in all allowed exit ports
      #
      exit_ports = []
      for filename in glob.glob("/etc/tor/torrc.d/*") + (glob.glob("/etc/tor/*")):
        if os.path.isfile(filename):
          inputfile = open(filename)
          lines = inputfile.readlines()
          inputfile.close()
          for line in lines:
            if line.startswith("ExitPolicy accept "):
              for word in line.split():
                if '*:' in word:    # do consider classX ports
                  port = int (word.split(':')[1])
                  exit_ports.append(port)

      try:
        t1 = time.time()

        Prev = Curr.copy()
        Curr.clear()

        pid = controller.get_info("process/pid")
        connections = get_connections(resolver=resolver, process_pid=pid,process_name='tor')

        t2 = time.time()

        policy = controller.get_exit_policy()
        for conn in connections:
          laddr, raddr = conn.local_address, conn.remote_address
          lport, rport = conn.local_port,    conn.remote_port

          # ignore incoming connections
          #
          if (lport == ORPort  and laddr == '5.9.158.75') or (lport == ORPort6  and laddr == '2a01:4f8:190:514a::2'):
              continue
          if (lport == DirPort and laddr == '5.9.158.75') or (lport == DirPort6 and laddr == '2a01:4f8:190:514a::2'):
              continue

          if raddr in relays:
            if rport in relays[raddr]:
              continue

          if not policy.can_exit_to(raddr, rport):
            continue

          # store the connections itself instead just counting them here
          # b/c we have to calculate the diff of 2 sets later
          #
          Curr.setdefault(rport, []).append(str(lport)+':'+raddr)

        if first == 1:
          Prev = Curr.copy()

        delta12 = t2-t1

        os.system('clear')
        print ("  port     # open/s clos/s      max                ( %s %i conns %.2f sec ) " % (resolver, len(connections), delta12))
        lines = 0;
        ports = set(list(Curr.keys()) + list(Prev.keys()) + list(MaxAll.keys()))
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
          n_opened = len(c-p)
          n_closed = len(p-c)

          MaxAll.setdefault(port, 0)
          MaxOpened.setdefault(port, 0)
          MaxClosed.setdefault(port, 0)

          if first == 0:
            if MaxAll[port] < n_curr:
              MaxAll[port]    = n_curr
            if MaxOpened[port] < n_opened:
              MaxOpened[port] = n_opened
            if MaxClosed[port] < n_closed:
              MaxClosed[port] = n_closed

          stri = " %5i %5i %6i %6i   %6i %6i %6i  (%s)" % (port, n_curr, n_opened, n_closed, MaxAll[port], MaxOpened[port], MaxClosed[port], port_usage(port))
          print (stri.replace(' 0', '  '))

          lines += 1
          if lines % 5 == 0:
            print

        first = 0

      except KeyboardInterrupt:
        break

if __name__ == '__main__':
  main()
