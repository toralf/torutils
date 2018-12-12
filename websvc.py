#!/usr/bin/env python
#

import socket
import argparse
import re
import sys
import logging

if sys.version_info[0] == 3:
  from http.server import HTTPServer, SimpleHTTPRequestHandler
else:
  from BaseHTTPServer   import HTTPServer
  from SimpleHTTPServer import SimpleHTTPRequestHandler


class HTTPServerV6(HTTPServer):
  address_family = socket.AF_INET6

class MyHandler(SimpleHTTPRequestHandler):
  def do_GET(self):
    logging.debug(self.requestline)
    return SimpleHTTPRequestHandler.do_GET(self)

def main():
  address = 'localhost'
  port = 1234
  ipv6 = "n"

  # set this to logging.DEBUG to see each request
  #
  logging.basicConfig(format='%(asctime)s %(name)s %(levelname)s + %(message)s', level=logging.INFO)

  logging.debug('Parsing args...')
  parser = argparse.ArgumentParser()
  parser.add_argument("--address", help="default: " + address)
  parser.add_argument("--port", help="default: " + str(port))
  parser.add_argument("--is_ipv6", help="mandatory if parameter for --address is an IPv6 hostname, default: " + ipv6)
  args = parser.parse_args()

  if args.address:
    address = str(args.address).replace('[','').replace(']','')

  if args.port:
    port = int(args.port)

  if args.is_ipv6:
      ipv6 = str(args.is_ipv6)
  else:
    if re.match (":", address):
      ipv6 = "y"

  if ipv6 == "y":
    server = HTTPServerV6((address, port), MyHandler)
  else:
    server = HTTPServer((address, port), MyHandler)

  logging.info('Starting ...')
  server.serve_forever()

if __name__ == '__main__':
  main()
