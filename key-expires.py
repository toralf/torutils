#!/usr/bin/env python3

# put out the time (in seconds) before the key expires
# appropriate cron job:
# @daily    let n="$(/opt/torutils/key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400"; [[ $n -lt 35 ]] && echo "Tor key is expiring in less than $n day(s)"

import codecs
import sys
import time

# eg.: /var/lib/tor/data2/keys/ed25519_signing_cert
#
with open(sys.argv[1], 'rb') as f:
    cert = f.read()
    expire = int(codecs.encode(cert[35:38], 'hex'), 16) * 3600
    now = time.time()
    print(int(expire-now))
