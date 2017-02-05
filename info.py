#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
 produces an output like:

 0.3.0.3-alpha   10:53:12   Exit  Fast  Guard  Running  Stable  V2Dir  Valid

  --------------------   port   ipv4  ipv6

  => relay ORPort                  1     0
  CtrlPort <= local                1     0
  ORPort   <= outer                1     0
  ORPort   <= relay                1     0

  => exit                  81     10     0
  => exit                  88      1     0
  => exit                 143      2     0
  => exit                 443   1089   713
...
  => exit               50002     11     0
  => relay port          8333      2     0

 exits:
 v4 : 1252
 v6:  718
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
    print ()

    policy = controller.get_exit_policy()
    connections = get_connections(resolver='lsof',process_name='tor')

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
        elif (lport == ControlPort):
          inc_ports_int('CtrlPort <= local')
        else:
          inc_ports_ext ('=> non exit port')

    # print out the amount of ports_ext
    #
    print ('  --------------------   port   ipv4  ipv6')
    print ()

    for t in sorted(ports_int):
      description = t
      v4, v6 = ports_int[t]
      print ("  %-20s  %5s  %5s %5s" % (description, '', str(v4) if v4 > 0 else '', str(v6) if v6 > 0 else ''))
    print ()

    sum = {'v4':0, 'v6':0};
    for t in sorted(ports_ext):
      description, port = t
      v4, v6 = ports_ext[t]
      if description == '=> exit':
        sum['v4'] += v4
        sum['v6'] += v6
      print ("  %-20s  %5i  %5s %5s" % (description, port, str(v4) if v4 > 0 else '', str(v6) if v6 > 0 else ''))
    print ()

    print ("  %-20s  %5s  %5i %5i" % ('=> exit', '', sum['v4'], sum['v6']))
    print ()

if __name__ == '__main__':
  main()
