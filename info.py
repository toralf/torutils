#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
$> info.py --ctrlport 29051
 0.3.2.7-rc   21:33:06   Exit  Fast  Guard  Running  Stable  V2Dir  Valid

  description         port   ipv4  ipv6  service
  -----------------  -----   ----  ----  -------------
  => relay ORport             396
  CtrlPort <= local             1
  ORport   <= outer            80     4
  ORport   <= relay          3382

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

import datetime
import stem.descriptor.collector

#import os
#import logging
#import stem.util.log

def main():
  ctrlport = 9051
  resolver = 'proc'

  #handler = logging.FileHandler('/tmp/stem_debug')
  #handler.setFormatter(logging.Formatter(
    #fmt = '%(asctime)s [%(levelname)s] %(message)s',
    #datefmt = '%m/%d/%Y %H:%M:%S',
  #))

  #log = stem.util.log.get_logger()
  #log.setLevel(logging.DEBUG)
  #log.addHandler(handler)

  #stem.util.connection.LOG_CONNECTION_RESOLUTION = True

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
      ORport   = None
      ORport6  = None
      DIRport  = None
      DIRport6 = None

      for address, port in controller.get_listeners(Listener.OR):
        if is_valid_ipv4_address(address):
          ORport = port
        else:
          ORport6 = port

      for address, port in controller.get_listeners(Listener.DIR):
        if is_valid_ipv4_address(address):
          DIRport = port
        else:
          DIRport6 = port

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

    print (" %s   %s   %s" % (version, datetime.timedelta(seconds=uptime), "  ".join(flags)))

    policy = controller.get_exit_policy()

    pid = controller.get_info("process/pid")
    connections = get_connections(resolver=resolver,process_pid=pid,process_name='tor')
    print (" resolver=%s  pid=%s  conns=%i" % (resolver, pid, len(connections)))

    relaysOr  = {}
    relaysDir = {}

    back = datetime.datetime.utcnow() - datetime.timedelta(days = 1)
    for s in stem.descriptor.collector.get_server_descriptors(start = back):
      relaysOr.setdefault(s.address, []).append(s.or_port)
      relaysDir.setdefault(s.address, []).append(s.dir_port)

    # classify network connections by port and flow direction
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
      inc_ports (ports_int, (description))

    def inc_ports_ext (description):
      inc_ports (ports_ext, (description, rport))

    # classify each connection
    #
    relays = {}
    for conn in connections:
      if conn.protocol == 'udp':
          continue

      laddr, raddr = conn.local_address, conn.remote_address
      lport, rport = conn.local_port,    conn.remote_port

      if raddr in relaysOr:
        if (lport == ORport and not conn.is_ipv6) or (lport == ORport6 and conn.is_ipv6):
          inc_ports_int('ORport   <= relay')
          relays[raddr] = relays.get(raddr,0)+1
        elif (lport == DIRport and not conn.is_ipv6) or (lport == DIRport6 and conn.is_ipv6):
          inc_ports_int('DIRport   <= relay')
        elif rport in relaysOr[raddr]:
          inc_ports_int('=> relay ORport')
          relays[raddr] = relays.get(raddr,0)+1
        else:
          # a system hosts beside a Tor relay another service too -or- a not (yet) known Tor relay
          #
          inc_ports_ext ('=> relay port')

      elif raddr in relaysDir:
        if rport in relaysDir[raddr]:
          inc_ports_int('=> relay DIRport')
        else:
          inc_ports_int('?? relay DIRport')

      elif policy.can_exit_to(raddr, rport):
        inc_ports_ext ('=> exit')

      else:
        if (lport == ORport and not conn.is_ipv6)    or (lport == ORport6 and conn.is_ipv6):
          inc_ports_int('ORport   <= outer')
        elif (lport == DIRport and not conn.is_ipv6) or (lport == DIRport6 and conn.is_ipv6):
          inc_ports_int('DIRport  <= outer')
        elif lport == ControlPort:
          inc_ports_int('CtrlPort <= local')
        else:
          inc_ports_ext ('?? non/down relay')
          #print ("%s %s  =  %s %s" % (laddr, lport, raddr, rport))

    count = {}
    for r in sorted(relays):
      n = relays[r]
      count[n] = count.get(n,0) + 1
    print (" relays: %5i" % len(list(relays)))
    for i in sorted(count):
      print ("         %5i with %2i connections" % (count[i], i))

    print ()
    print ('  description         port   ipv4  ipv6  servicename')
    print ('  -----------------  -----   ----  ----  -------------')

    sum4 = 0
    sum6 = 0
    for t in sorted(ports_int):
      description = t
      v4, v6 = ports_int[t]
      sum4 += v4
      sum6 += v6
      print ("  %-17s  %5s  %5s %5s" % (description, '', str(v4) if v4 > 0 else '', str(v6) if v6 > 0 else ''))
    print ("")

    exit4 = 0
    exit6 = 0
    for t in sorted(ports_ext):
      description, port = t
      v4, v6 = ports_ext[t]
      sum4 += v4
      sum6 += v6
      if description == '=> exit':
        exit4 += v4
        exit6 += v6
      print ("  %-17s  %5i  %5s %5s  %s" % (description, port, str(v4) if v4 > 0 else '', str(v6) if v6 > 0 else '', port_usage(port)))
    print ("")

    print ("  %17s  %5s  %5i %5i" % ('sum', '', sum4, sum6))
    print ("  %17s  %5s  %5i %5i" % ('exits among them', '', exit4, exit6))

if __name__ == '__main__':
  main()
