#!/usr/bin/env python
# -*- coding: utf-8 -*-

# country based stats of a Tor relay
#

import datetime
from collections import Counter
from stem.control import Controller
from stem.util.connection import get_connections, port_usage, is_valid_ipv4_address

def main():
  with Controller.from_port(port=9051) as controller:
    controller.authenticate()

    # our version, uptime and relay flags
    #
    version = str(controller.get_version()).split()[0]
    try:
      srv = controller.get_server_descriptor()
      uptime = srv.uptime
      flags = controller.get_network_status(relay=srv.nickname).flags;
    except Exception as Exc:
      print (Exc)
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

    IPv4, IPv6 = 0, 0

    policy = controller.get_exit_policy()
    connections = get_connections(resolver='lsof',process_name='tor')

    ORPort   = int(controller.get_conf("ORPort"))
    ControlPort = int(controller.get_conf("ControlPort"))
    DirPort = int(controller.get_conf("DirPort"))

    for conn in connections:
      if conn.protocol == 'udp':
          continue

      laddr, raddr = conn.local_address, conn.remote_address

      if is_valid_ipv4_address(raddr):
        IPv4 += 1
      else:
        IPv6 += 1

      country = controller.get_info("ip-to-country/%s" % raddr, 'xx')
      lport, rport = conn.local_port, conn.remote_port

      if raddr in relays:
        if lport == ORPort:
          relay2ORPort[country] += 1
        elif rport in relays[raddr]:
          local2relayORPort[country] += 1
        else:
          # a relay hosts another service
          #
          local2relayOther[country] += 1
          local2relayOtherPorts[rport] += 1

      elif policy.can_exit_to(raddr, rport):
        ExitPorts[rport] += 1
        if rport not in [80, 81, 443]:
          ExitWithoutWWW[country] += 1

      else:
        if lport == ORPort:
          outer2ORPort[country] += 1
        elif lport == DirPort:
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
