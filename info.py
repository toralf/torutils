#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
$> info.py --ctrlport 29051
 0.3.2.7-rc   21:33:06   Exit  Fast  Guard  Running  Stable  V2Dir  Valid

  description         port   ipv4  ipv6  service
  -----------------  -----   ----  ----  -------------
  => relay ORPort             396
  CtrlPort <= local             1
  ORPort   <= outer            80     4
  ORPort   <= relay          3382

  => exit              443    611   232  HTTPS
  => exit              587      1        SMTP
  => exit              993     14        IMAPS
  => exit              995      2        POP3S
  => exit             5222     35        Jabber
  => exit             5223     20        Jabber
  => exit             6667      1        IRC
  => exit             7777      1        None
  => exit             8233      1     1  None
  => exit             8333     14     1  Bitcoin
  => exit            50002     11        Electrum Bitcoin SSL

     sum                      711   234

  => non exit port    9002      1        None
  => relay port       5222      5        Jabber
  => relay port      50002      2        Electrum Bitcoin SSL
"""

import datetime
from collections import Counter
import argparse
import sys

from stem.control import Controller, Listener
from stem.util.connection import get_connections, port_usage, is_valid_ipv4_address

def main():
  ctrlport = 9051
  resolver = 'lsof'

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
      return

    # our version, uptime and flags
    #
    version = str(controller.get_version()).split()[0]
    uptime = 0
    flags = ''

    try:
      descriptor = controller.get_server_descriptor()
      uptime = descriptor.uptime
      flags = controller.get_network_status(relay=descriptor.fingerprint).flags
    except Exception as Exc:
      print (Exc)

    print (" %s   %s   %s\n" % (version, datetime.timedelta(seconds=uptime), "  ".join(flags)))

    policy = controller.get_exit_policy()
    pid = controller.get_info("process/pid")
    connections = get_connections(resolver=resolver,process_pid=pid)

    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    # classify network connections by port and country
    #
    ports_int = {}
    ports_ext = {}

    def inc_ports (ports, t):
      v4, v6 = ports.get(t,(0,0))
      if conn.is_ipv6:
        ports[t] = (v4, v6+1)
      else:
        ports[t] = (v4+1, v6)

    def inc_ports_int (description):
      t = (description)
      inc_ports (ports_int, t)

    def inc_ports_ext (description):
      t = (description, rport)
      inc_ports (ports_ext, t)

    # now run over all connections
    #
    for conn in connections:
      if conn.protocol == 'udp':
          continue

      laddr, raddr = conn.local_address, conn.remote_address
      lport, rport = conn.local_port,    conn.remote_port

      if raddr in relays:
        if not conn.is_ipv6 and lport == ORPort or conn.is_ipv6 and lport == ORPort6:
          inc_ports_int('ORPort   <= relay')
        elif rport in relays[raddr]:
          inc_ports_int('=> relay ORPort')
        else:
          # a server hosts beside a Tor relay another service too
          #
          inc_ports_ext ('=> relay port')

      elif policy.can_exit_to(raddr, rport):
        inc_ports_ext ('=> exit')

      else:
        if not conn.is_ipv6 and lport == ORPort or conn.is_ipv6 and lport == ORPort6:
          inc_ports_int('ORPort   <= outer')
        elif not conn.is_ipv6 and lport == DirPort or conn.is_ipv6 and lport == DirPort6:
          inc_ports_int('DirPort  <= outer')
        elif lport == ControlPort:
          inc_ports_int('CtrlPort <= local')
        else:
          inc_ports_ext ('=> non exit port')

    # print out the amount of ports_ext
    #
    print ('  description         port   ipv4  ipv6  service')
    print ('  -----------------  -----   ----  ----  -------------')

    for t in sorted(ports_int):
      description = t
      v4, v6 = ports_int[t]
      print ("  %-17s  %5s  %5s %5s" % (description, '', str(v4) if v4 > 0 else '', str(v6) if v6 > 0 else ''))

    print

    count4 = 0
    count6 = 0
    sum_was_printed = 0
    for t in sorted(ports_ext):
      description, port = t
      v4, v6 = ports_ext[t]
      if description == '=> exit':
        count4 += v4
        count6 += v6
      else:
        if not sum_was_printed:
          print ("\n  %-17s  %5s  %5i %5i\n" % ('   sum', '', count4, count6))
          sum_was_printed = 1

      print ("  %-17s  %5i  %5s %5s  %s" % (description, port, str(v4) if v4 > 0 else '', str(v6) if v6 > 0 else '', port_usage(port)))

if __name__ == '__main__':
  main()
