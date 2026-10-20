#!/usr/bin/env python3
"""A stand-in for `dig -x <ip> @224.0.0.251 -p 5353 +short`: only the address ending .40 has a name on the network."""
import sys

address = sys.argv[sys.argv.index("-x") + 1] if "-x" in sys.argv else ""
if address.endswith(".40"):
    print("mini-40.local.")
