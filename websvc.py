#!/usr/bin/env python
#

import socket
from BaseHTTPServer import HTTPServer
from SimpleHTTPServer import SimpleHTTPRequestHandler
 
class MyHandler(SimpleHTTPRequestHandler):
  def do_GET(self):
    return SimpleHTTPRequestHandler.do_GET(self)
 
class HTTPServerV6(HTTPServer):
  address_family = socket.AF_INET6
 
def main():
  server = HTTPServerV6(('::', 8080), MyHandler)
  #server = HTTPServer(('127.0.0.1', 8080), MyHandler)
  server.serve_forever()
 
if __name__ == '__main__':
  main()
