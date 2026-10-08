#!/usr/bin/env python3
"""A stand-in for nmap. Prints fixture XML. Logs every call to $FAKE_NMAP_LOG, sleeps $FAKE_NMAP_DELAY seconds first."""
import json
import os
import sys
import time

args = sys.argv[1:]
if os.environ.get("FAKE_NMAP_LOG"):
    with open(os.environ["FAKE_NMAP_LOG"], "a") as log:
        log.write(json.dumps(args) + "\n")
time.sleep(float(os.environ.get("FAKE_NMAP_DELAY", "0")))
if os.environ.get("FAKE_NMAP_FAIL"):
    sys.exit(3)

AGENT_PORT_HOSTS = {"60"}
SWEEP = [("1", "AA:BB:CC:00:00:01", "MikroTik", "router.lan"), ("40", None, None, None), ("60", None, None, None), ("90", None, None, None)]


def host(prefix, last, mac=None, vendor=None, name=None, port=None):
    parts = [f'<host><status state="up"/><address addr="{prefix}.{last}" addrtype="ipv4"/>']
    if mac:
        parts.append(f'<address addr="{mac}" addrtype="mac" vendor="{vendor}"/>')
    if name:
        parts.append(f'<hostnames><hostname name="{name}" type="PTR"/></hostnames>')
    if port:
        parts.append(f'<ports><port protocol="tcp" portid="{port[0]}"><state state="{port[1]}"/></port></ports>')
    parts.append("</host>")
    return "".join(parts)


if "-sn" in args:
    prefix = args[-1].rsplit(".", 1)[0]
    body = "".join(host(prefix, last, mac, vendor, name) for last, mac, vendor, name in SWEEP)
else:
    port = args[args.index("-p") + 1]
    ips = [a for a in args if a.count(".") == 3 and not a.startswith("-")]
    body = "".join(host(ip.rsplit(".", 1)[0], ip.rsplit(".", 1)[1], port=(port, "open")) for ip in ips if ip.rsplit(".", 1)[1] in AGENT_PORT_HOSTS)
print(f'<?xml version="1.0"?><nmaprun scanner="nmap">{body}</nmaprun>')
