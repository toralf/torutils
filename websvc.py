#!/usr/bin/env python
#

import socket
from BaseHTTPServer import HTTPServer
from SimpleHTTPServer import SimpleHTTPRequestHandler
import argparse
import re

class MyHandler(SimpleHTTPRequestHandler):
  def do_GET(self):
    return SimpleHTTPRequestHandler.do_GET(self)
 
class HTTPServerV6(HTTPServer):
  address_family = socket.AF_INET6
 
def main():
  is_ipv6 = True
  address = '::1'
  port = 8080

  parser = argparse.ArgumentParser()
  parser.add_argument("--address", help="default: " + address + ")")
  parser.add_argument("--port", help="default: " + str(port) + ")")
  parser.add_argument("--is_ipv6", help="default: n)")
  args = parser.parse_args()

  if args.address:
    address = str(args.address)

  if args.port:
    port = int(args.port)

  if re.match (":", address):
    is_ipv6 = True
  else:
    is_ipv6 = False

  if args.is_ipv6:
    if args.is_ipv6 == "n":
      is_ipv6 = False
    else:
      is_ipv6 = True

  if is_ipv6:
    server = HTTPServerV6((address, port), MyHandler)
  else:
    server = HTTPServer((address, port), MyHandler)

  server.serve_forever()

if __name__ == '__main__':
  main()
