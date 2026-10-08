#!/usr/bin/env python3
"""A stand-in for `arp -an`. The subnet prefix comes from $FAKE_ARP_PREFIX."""
import os

prefix = os.environ.get("FAKE_ARP_PREFIX", "192.168.100")
print(f"? ({prefix}.1) at aa:bb:cc:0:0:1 on en0 ifscope [ethernet]")
print(f"? ({prefix}.40) at 0:1a:2b:3c:4d:40 on en0 ifscope permanent [ethernet]")
print(f"? ({prefix}.60) at aa:bb:cc:0:0:60 on en0 ifscope [ethernet]")
print(f"? ({prefix}.90) at (incomplete) on en0 ifscope [ethernet]")
