#!/usr/bin/env python
# -*- coding: utf-8 -*-

import fileinput
import ipaddress

for address in fileinput.input():
    print(ipaddress.IPv6Address(address.strip()).exploded)

