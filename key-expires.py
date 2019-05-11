#!/usr/bin/env python3

# put out the time (in seconds) before the key expires

import codecs
import sys
import time

with open('/var/lib/' + sys.argv[1] + '/data/keys/ed25519_signing_cert', 'rb') as f:
    cert = f.read()
    expire = int(codecs.encode(cert[35:38], 'hex'), 16) * 3600
    now = time.time()
    print(int(expire-now))
