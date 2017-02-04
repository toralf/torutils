#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
 produces an output like:

 0.3.0.3-alpha   1:10:40   Exit  Fast  Guard  Running  Stable  V2Dir  Valid
  v4 => relay ORPort         218
  v4 CtrlPort <= local         1
  v4 DirPort  <= outer         2
  v4 ORPort   <= outer       125
  v4 ORPort   <= relay      4035
  v6 ORPort   <= outer         3

  v4 => exit                  81      8
  v4 => exit                  88      1
...
  v4 => non exit port       9001      1
  v4 => relay port          8333      2
  v6 => exit                 443    616
  v6 => exit                8333      1


 exits:
 v4 : 1265
 v6:  617
"""

import datetime
from collections import Counter

from stem.control import Controller, Listener
from stem.util.connection import get_connections, port_usage, is_valid_ipv4_address, is_valid_ipv6_address

def main():

  with Controller.from_port(port=9051) as controller:
    controller.authenticate()

    try:
      ControlPort = int(controller.get_conf("ControlPort"))

      for listener in controller.get_listeners(Listener.OR):
        address, port = listener
        if is_valid_ipv4_address(address):
          ORPort = port
        elif is_valid_ipv6_address(address):
          ORPort6 = port
        else:
          print ("Woops, can't parse get_listeners(Listener.OR)")
          return

      for listener in controller.get_listeners(Listener.DIR):
        address, port = listener
        if is_valid_ipv4_address(address):
          DirPort = port
        elif is_valid_ipv6_address(address):
          DirPort6 = port
        else:
          print ("Woops, can't get listeners)")
          return

    except Exception as Exc:
      print ("Woops, ports aren't configured")
      #print (Exc)
      return

    # our version, uptime and relay flags
    #
    version = str(controller.get_version()).split()[0]

    try:
      srv = controller.get_server_descriptor()
      uptime = srv.uptime
      flags = controller.get_network_status(relay=srv.nickname).flags;
    except Exception as Exc:
      print ("Woops, can't get descriptor")
      #print (Exc)
      uptime = 0
      flags = ''

    print (" %s   %s   %s" % (version, datetime.timedelta(seconds=uptime), "  ".join(flags)))

    policy = controller.get_exit_policy()
    connections = get_connections(resolver='lsof',process_name='tor')

    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    # classify network connections by port and country
    #
    ports_int = {}
    ports_ext = {}

    def inc_ports_int (description):
      if conn.is_ipv6:
        version = 'v6'
      else:
        version = 'v4'
      t = (version, description)
      ports_int[t] = ports_int.get(t,0) + 1

    def inc_ports_ext (description):
      if conn.is_ipv6:
        version = 'v6'
      else:
        version = 'v4'
      t = (version, description, rport)
      ports_ext[t] = ports_ext.get(t,0) + 1

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
        elif (lport == ControlPort):
          inc_ports_int('CtrlPort <= local')
        else:
          inc_ports_ext ('=> non exit port')

    # print out the amount of ports_ext
    #
    sum = {'v4':0, 'v6':0};
    for t in sorted(ports_int):
      version, name = t
      print ("  %s %-20s  %5s" % (version, name, ports_int[t]))
    print ("\n")

    for t in sorted(ports_ext):
      version, name, port = t
      if name == '=> exit':
        sum[version] += ports_ext[t]
      print ("  %s %-20s  %5s  %5i" % (version, name, port, ports_ext[t]))
    print ("\n")

    print (" exits:\n v4 :%5i\n v6:%5i" % (sum['v4'], sum['v6']))
    print ("\n")

if __name__ == '__main__':
  main()
