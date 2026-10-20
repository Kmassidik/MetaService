#!/usr/bin/env python3
"""Looks at this computer and says whether the parent can run here and which install fits it, in plain words.

Prints one line per finding: "ok", "warn" or "stop", then the text. Exit 0 when the parent can run here, 1 when it cannot.
Usage: check_computer.py
"""
import ipaddress
import os
import platform
import re
import shutil
import subprocess
import sys

# The same places the Mac Agent looks for Apple's container tool (ProcessContainerCLI.searchPaths in the Agent, ComputerChecks.containerPaths in the parent).
CONTAINER_PATHS = tuple(os.environ.get("METASERVICE_CONTAINER_PATHS", "/usr/local/bin/container /opt/homebrew/bin/container /usr/bin/container").split())
WINDOWS_NAMES = ("windows", "mingw", "msys", "cygwin")


NMAP_PATHS = tuple(os.environ.get("METASERVICE_NMAP_PATHS", "/opt/homebrew/bin/nmap /usr/local/bin/nmap /usr/bin/nmap /run/current-system/sw/bin/nmap").split())


def assess(system, machine, has_swift, container_found, nmap_found=None):
    """What this computer is and whether it can run the parent. Returns a list of (level, text), where "stop" means the parent cannot run here."""
    kind = system.lower()
    if kind.startswith(WINDOWS_NAMES):
        return [("stop", "Windows is not supported yet. Run the parent on an Apple Silicon Mac. Linux machines can be added to it later.")]
    if kind == "linux":
        return [("stop", f"Linux ({machine}): the parent does not run on Linux yet. Run it on an Apple Silicon Mac, and add this Linux computer as a machine from there.")]
    if kind != "darwin":
        return [("stop", f"{system} is not supported.")]
    if machine != "arm64":
        return [("stop", f"An Intel Mac ({machine}): the parent is built for Apple Silicon only.")]
    findings = [("ok", "Apple Silicon Mac. The macOS install fits this computer.")]
    findings.append(("ok", "Swift found.") if has_swift else ("stop", "Swift is missing. Install Xcode or its command-line tools (xcode-select --install), then run this again."))
    findings.append(("ok", "Apple's container tool found.") if container_found else
                    ("warn", "Apple's container tool is not installed, so this Mac cannot create VMs yet. The install adds it for you (or use --skip-container to go without)."))
    if nmap_found is not None:
        findings.append(("ok", "nmap found.") if nmap_found else
                        ("warn", "nmap is not installed, so Find machines sees fewer computers. The install adds it for you with Homebrew (or use --skip-nmap to go without)."))
    return findings


WIDEST_SCAN_PREFIX = 22  # the Root scans a /22 (1024 addresses) at most; keep this in step with Subnet.widestPrefix


def describe_network(route_text: str, ifconfig_text: str):
    """What network this Mac is on, as one (level, text) finding. Takes the text of `route -n get default` and of `ifconfig <interface>`."""
    interface = re.search(r"interface:\s*(\S+)", route_text)
    found = re.search(r"inet (\d+\.\d+\.\d+\.\d+) netmask (0x[0-9a-fA-F]+)", ifconfig_text)
    if not interface or not found:
        return ("warn", "No network address found. Find machines needs this Mac on a network (Wi-Fi or Ethernet).")
    address = ipaddress.ip_interface(f"{found.group(1)}/{ipaddress.ip_address(int(found.group(2), 16))}")
    network, where = address.network, f"this Mac is {address.ip} on {interface.group(1)}"
    if not address.ip.is_private:
        return ("warn", f"This Mac's address {address.ip} is public, not a private network, so Find machines has nothing to scan. Set SCAN_SUBNET in .env if it is also on a private one.")
    if network.prefixlen < WIDEST_SCAN_PREFIX:
        return ("warn", f"The network {network} ({where}) is too big to scan (the largest is /{WIDEST_SCAN_PREFIX}). Set SCAN_SUBNET in .env to the part you want, for example {address.ip}/24 with the last number as 0.")
    return ("ok", f"Network {network} ({where}). Find machines scans it.")


def look_at_network():
    def run(command):
        return subprocess.run(command, capture_output=True, text=True, timeout=10).stdout

    route_text = run(["route", "-n", "get", "default"])
    interface = re.search(r"interface:\s*(\S+)", route_text)
    return describe_network(route_text, run(["ifconfig", interface.group(1)]) if interface else "")


def main():
    nmap_found = any(os.access(path, os.X_OK) for path in NMAP_PATHS) or shutil.which("nmap") is not None
    findings = assess(platform.system() or sys.platform, platform.machine(), shutil.which("swift") is not None, any(os.access(path, os.X_OK) for path in CONTAINER_PATHS), nmap_found)
    if not any(level == "stop" for level, _ in findings):
        findings.append(look_at_network())
    marks = {"ok": "✓", "warn": "!", "stop": "✗"}
    for level, text in findings:
        print(f"      {marks[level]} {text}")
    return 1 if any(level == "stop" for level, _ in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
