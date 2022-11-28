#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
# -*- coding: utf-8 -*-

import fileinput
import ipaddress

for address in fileinput.input():
  print(ipaddress.IPv6Address(address.strip()).exploded)
