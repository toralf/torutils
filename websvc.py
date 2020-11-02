#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
from http.server import HTTPServer, SimpleHTTPRequestHandler
import logging
import re
import socket


class HTTPServerV6(HTTPServer):
    address_family = socket.AF_INET6


class MyHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        logging.debug(self.requestline)
        return SimpleHTTPRequestHandler.do_GET(self)


def main():
    logging.basicConfig(format='%(asctime)s %(name)s %(levelname)s + %(message)s',
                        level=logging.INFO)

    logging.debug('Parsing args...')
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="default: localhost", default='localhost')
    parser.add_argument("--port", type=int, help="default: 1234", default=1234)
    parser.add_argument("--is_ipv6", type=bool, help="set it if ADDRESS is an IPv6, default: False",
                        default=False)
    args = parser.parse_args()

    if args.is_ipv6 or re.match(":", args.address):
        address = str(args.address).replace('[', '').replace(']', '')
        server = HTTPServerV6((address, args.port), MyHandler)
    else:
        server = HTTPServer((args.address, args.port), MyHandler)

    logging.info('running at %s at %s', args.address, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt as e:
        print(e)


if __name__ == '__main__':
    main()
