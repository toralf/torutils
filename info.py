#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
# country based stats of a Tor relay
# eg.:

 0.2.8.2-alpha-dev   10:54:53   Exit  Fast  Guard  Running  Stable  V2Dir  Valid
 overall            4818   IPv4: 4816   IPv6:    2
 CtrlPort <= local     1   ??  1
 DirPort  <= outer     0
 ORPort   <= outer    39   de 10    us 10    nl  7    es  2    fr  2    se  2    id  2    ru  1
 ORPort   <= relay  3311   de686    us609    fr521    nl263    gb178    ru167    ca130    se125
 => relay ORPort      32   fr 11    us  5    nl  4    de  2    ru  2    dk  1    it  1    bg  1
 => relay port         1   lt  1
            :50002     1 (Electrum Bitcoin SSL)
 => non exit port      0
 => exit w/o www     116   us 59    de 15    ru  5    fr  5    se  4    cn  4    jp  3    nl  3
            :   81     7 (HTTP Alternate)
            :  443  1311 (HTTPS)
            :  993    10 (IMAPS)
            : 1863     1 (MSNP)
            : 5050     1 (Yahoo IM)
            : 5190     3 (AIM/ICQ)
            : 5222    25 (Jabber)
            : 5228    35 (Android Market)
            : 6667     4 (IRC)
            : 6697     2 (IRC)
            : 8082     5 (None)
            : 8333     9 (Bitcoin)
            : 8443     1 (PCsync HTTPS)
            : 9999     1 (distinct)
            :50002    19 (Electrum Bitcoin SSL)
"""

import datetime
from collections import Counter
from stem.control import Controller
from stem.util.connection import get_connections, port_usage, is_valid_ipv4_address, is_valid_ipv6_address
from stem.control import Listener

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
          print ("Woops, can't parse get_listeners(Listener.DIR)")
          return

    except Exception as Exs:
      print ("Woops, ports aren't configured")
      return

    # our version, uptime and relay flags
    #
    version = str(controller.get_version()).split()[0]

    try:
      srv = controller.get_server_descriptor()
      uptime = srv.uptime
      flags = controller.get_network_status(relay=srv.nickname).flags;
    except Exception as Exc:
      print ("Can' get descriptors (yet)")
      uptime = 0
      flags = ''

    print (" %s   %s   %s" % (version, datetime.timedelta(seconds=uptime), "  ".join(flags)))

    # classify network connections by port and country
    #
    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    class Country(Counter):
      def __init__(self, name="<none>"):
        self.name = name

      def __str__(self):
        ret=""
        for tupel in self.most_common(8):
          ret += "%s%3i    " % tupel
        return " %-17s %5i   %s" % (self.name, sum(self.values()), ret)

    class Port(Counter):
      def __str__(self):
        ret = ""
        for port in sorted(self.keys()):
          ret += "            :%5i  %4i (%s)\n" % (port, self[port], port_usage(port))
        return ret.rstrip("\n")

    Local2Controlport     = Country(name="CtrlPort <= local")
    outer2DirPort         = Country(name="DirPort  <= outer")
    outer2ORPort          = Country(name="ORPort   <= outer")
    relay2ORPort          = Country(name="ORPort   <= relay")

    local2relayORPort     = Country(name="=> relay ORPort")
    local2relayOther      = Country(name="=> relay port")
    local2relayOtherPorts = Port()
    nonExit               = Country(name="=> non exit port")
    NonExitPorts          = Port()
    ExitWithoutWWW        = Country(name="=> exit w/o www")
    ExitPorts             = Port()

    noPolicy              = Country(name="! no policy")
    noPolicyPorts         = Port()

    IPv4, IPv6 = 0, 0     # just counters

    policy = controller.get_exit_policy()
    connections = get_connections(resolver='lsof',process_name='tor')

    for conn in connections:
      if conn.protocol == 'udp':
          continue

      laddr, raddr = conn.local_address, conn.remote_address

      if conn.is_ipv6:
        IPv6 += 1
      else:
        IPv4 += 1

      country = controller.get_info("ip-to-country/%s" % raddr, 'xx')
      lport, rport = conn.local_port, conn.remote_port

      if raddr in relays:
        if not conn.is_ipv6 and lport == ORPort or conn.is_ipv6 and lport == ORPort6:
          relay2ORPort[country] += 1
        elif rport in relays[raddr]:
          local2relayORPort[country] += 1
        else:
          # a server hosts beside a Tor relay another service too
          #
          local2relayOther[country] += 1
          local2relayOtherPorts[rport] += 1

      elif policy.can_exit_to(raddr, rport):
        ExitPorts[rport] += 1
        if rport not in [80, 81, 443]:
          ExitWithoutWWW[country] += 1

      else:
        if not conn.is_ipv6 and lport == ORPort or conn.is_ipv6 and lport == ORPort6:
          outer2ORPort[country] += 1
        elif not conn.is_ipv6 and lport == DirPort or conn.is_ipv6 and lport == DirPort6:
          outer2DirPort[country] += 1
        elif (lport == ControlPort):
          Local2Controlport[country] += 1
        else:
          nonExit[country] += 1
          NonExitPorts[rport] += 1

    print (" %-17s %5i   IPv4:%5i   IPv6:%5i" % ("overall", len(connections), IPv4, IPv6))

    print (Local2Controlport)
    print (outer2DirPort)
    print (outer2ORPort)
    print (relay2ORPort)

    print (local2relayORPort)
    print (local2relayOther)
    if (local2relayOtherPorts):
      print (local2relayOtherPorts)
    if (ExitPorts):
      print (nonExit)
      if (NonExitPorts):
        print (NonExitPorts)

      print (ExitWithoutWWW)
      print (ExitPorts)
    else:
      if (noPolicy):
        print (noPolicy)
        print (noPolicyPorts)


if __name__ == '__main__':
  main()
