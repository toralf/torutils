#!/usr/bin/env python
#

import socket
import argparse
import re
import sys
import random

if sys.version_info[0] == 3:
  from http.server import HTTPServer, SimpleHTTPRequestHandler
else:
  from BaseHTTPServer   import HTTPServer
  from SimpleHTTPServer import SimpleHTTPRequestHandler


class HTTPServerV6(HTTPServer):
  address_family = socket.AF_INET6

def main():
  is_ipv6 = False
  address = 'localhost'
  port = random.randint (1025,65535)

  parser = argparse.ArgumentParser()
  parser.add_argument("--address", help="default: " + address)
  parser.add_argument("--port", help="default: " + str(port))
  parser.add_argument("--is_ipv6", help="mandatory if parameter for --address is a hostname and should be IPv6, default: n")
  args = parser.parse_args()

  if args.address:
    address = str(args.address)

  if args.port:
    port = int(args.port)
  else:
    print ("port = %i" % port)

  if re.match (":", address):
    is_ipv6 = True
  else:
    if args.is_ipv6:
      if args.is_ipv6 == "y" or args.is_ipv6 == "Y":
        is_ipv6 = True

  if is_ipv6:
    server = HTTPServerV6((address, port), SimpleHTTPRequestHandler)
  else:
    server = HTTPServer((address, port), SimpleHTTPRequestHandler)

  server.serve_forever()


if __name__ == '__main__':
  main()
