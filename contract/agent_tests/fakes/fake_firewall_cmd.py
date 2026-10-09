#!/usr/bin/env python3
"""A stand-in for firewall-cmd as an ordinary user sees it: --state needs polkit and fails with nothing on stdout, while
--get-zone-of-interface=NAME answers from a zone file that a test can change while the Agent runs. "no zone" goes to stderr with exit code 2,
as on a real Fedora host. With FAKE_FIREWALL_RUNNING=0 (firewalld stopped) it fails with "FirewallD is not running"."""
import os
import sys

arg = sys.argv[1] if len(sys.argv) > 1 else ""
if arg == "--state":
    sys.stderr.write("Authorization failed.\n")
    sys.exit(253)
elif arg.startswith("--get-zone-of-interface="):
    if os.environ.get("FAKE_FIREWALL_RUNNING", "1") != "1":
        sys.stderr.write("FirewallD is not running\n")
        sys.exit(252)
    zone = open(os.environ["FAKE_FIREWALL_ZONE_FILE"]).read().strip()
    if zone == "no zone":  # what the real tool does for an interface in no zone: stderr and exit code 2
        sys.stderr.write("no zone\n")
        sys.exit(2)
    print(zone)
else:
    sys.exit(2)
