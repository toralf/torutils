#!/usr/bin/env python
# -*- coding: utf-8 -*-

# country based stats of a Tor relay
#
# eg.:
#
# 0.2.8.2-alpha   1 day, 6:04:51   Exit  Fast  Guard  Running  Stable  V2Dir  Valid
# overall            5664   IPv4: 5663   IPv6:    1
# CtrlPort <= local     1   ??  1
# DirPort  <= outer     1   hu  1
# ORPort   <= outer    63   us 14    de 14    fr  8    nl  5    at  3    ua  2    hk  2    gb  2
# ORPort   <= relay  3220   de684    us582    fr522    nl266    gb155    ru152    ca125    se123
# => relay ORPort      34   fr 10    de  7    gb  3    ca  2    us  2    se  2    fi  2    au  1
# => relay port         4   us  2    gb  1    de  1
#            :  443     2 (HTTPS)
#            : 5222     1 (Jabber)
#            :50002     1 (Electrum Bitcoin SSL)
# => non exit port      1   ch  1
#            : 9001     1 (None)
# => exit w/o www     173   us 68    de 24    nl 15    ru 14    fr  8    ca  7    gb  5    jp  4
#            :   81     2 (HTTP Alternate)
#            :  443  2165 (HTTPS)
#            :  992     3 (Telnets)
#            :  993    14 (IMAPS)
#            :  995     1 (POP3S)
#            : 1500     7 (NetGuard)
#            : 3128     2 (SQUID)
#            : 3389     1 (WBT)
#            : 5050     1 (Yahoo IM)
#            : 5190     2 (AIM/ICQ)
#            : 5222    65 (Jabber)
#            : 5228    30 (Android Market)
#            : 6664     1 (IRC)
#            : 6667     4 (IRC)
#            : 8000     1 (iRDMI)
#            : 8082     1 (None)
#            : 8333    15 (Bitcoin)
#            : 8443     5 (PCsync HTTPS)
#            : 9999     2 (distinct)
#            :50002    18 (Electrum Bitcoin SSL)

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
          # a server hosts beside a Tor relay another service too
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
