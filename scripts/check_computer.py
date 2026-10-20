#!/usr/bin/env python3
"""Looks at this computer and says whether the parent can run here and which install fits it, in plain words.

Prints one line per finding: "ok", "warn" or "stop", then the text. Exit 0 when the parent can run here, 1 when it cannot.
Usage: check_computer.py
"""
import os
import platform
import shutil
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


def main():
    nmap_found = any(os.access(path, os.X_OK) for path in NMAP_PATHS) or shutil.which("nmap") is not None
    findings = assess(platform.system() or sys.platform, platform.machine(), shutil.which("swift") is not None, any(os.access(path, os.X_OK) for path in CONTAINER_PATHS), nmap_found)
    marks = {"ok": "✓", "warn": "!", "stop": "✗"}
    for level, text in findings:
        print(f"      {marks[level]} {text}")
    return 1 if any(level == "stop" for level, _ in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
