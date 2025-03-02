#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# -*- coding: utf-8 -*-

# put out the time (in seconds) before the medium-term signing Tor certs expires

# example call (as root):
# n=$(($(key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert) / 86400)); [[ $n -lt 35 ]] && echo "Tor cert expires in less than $n day(s)"

import codecs
import sys
import time

with open(sys.argv[1], "rb") as f:
    cert = f.read()
    expire = int(codecs.encode(cert[35:38], "hex"), 16)  # expiration timestamp in hours
    now = int(time.time())  # current timestamp in seconds
    print(3600 * expire - now)
