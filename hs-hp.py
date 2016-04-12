#!/usr/bin/python
# -*- coding: utf-8 -*-

import socket
import string
import sys
import logging

if len(sys.argv) != 4:
  print "\n Usage: "+sys.argv[0]+" <port> <logfile> <banner>"
  print "z.B: "+sys.argv[0]+" 6667 irc_6667.log 'irc-hs NOTICE * :*** Looking up your hostname...'\n"
  sys.exit(1)

port=sys.argv[1]
logfile=sys.argv[2]
banner=sys.argv[3]

logging.basicConfig(level=logging.DEBUG,
                    format='%(asctime)s %(levelname)s %(message)s',
                    filename=logfile,
                    filemode='a')

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR,1)
s.bind(("", int(port)))
s.listen(5)

while 1:
  try:
    (clientsock, clientaddr) = s.accept() 
    clienthost = clientsock.getpeername()[0]
    clientport = clientsock.getpeername()[1]
    clientsock.send(banner) 
    resp = clientsock.recv(1024)
    clientsock.close()
    logging.info(clienthost+":"+str(clientport)+ " "+resp)
  except(KeyboardInterrupt):
    sys.exit(1)
  except:
    continue
