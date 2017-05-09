#!/usr/bin/env python
#

import socket
import argparse
import re
import sys

if sys.version_info[0] == 3:
  from http.server import HTTPServer, SimpleHTTPRequestHandler
else:
  from BaseHTTPServer   import HTTPServer
  from SimpleHTTPServer import SimpleHTTPRequestHandler


class MyHandler(SimpleHTTPRequestHandler):
  def do_GET(self):
    return SimpleHTTPRequestHandler.do_GET(self)

class HTTPServerV6(HTTPServer):
  address_family = socket.AF_INET6


def main():
  is_ipv6 = False
  #address = '::1'
  address = 'localhost'
  port = 8080

  parser = argparse.ArgumentParser()
  parser.add_argument("--address", help="default: " + address)
  parser.add_argument("--port", help="default: " + str(port))
  parser.add_argument("--is_ipv6", help="mandatory if a given hostname for '--address' should be IPv6, default: n")
  args = parser.parse_args()

  if args.address:
    address = str(args.address)

  if args.port:
    port = int(args.port)

  if re.match (":", address):
    is_ipv6 = True
  else:
    if args.is_ipv6:
      if args.is_ipv6 == "y" or args.is_ipv6 == "Y":
        is_ipv6 = True

  if is_ipv6:
    server = HTTPServerV6((address, port), MyHandler)
  else:
    server = HTTPServer((address, port), MyHandler)

  server.serve_forever()

if __name__ == '__main__':
  main()
