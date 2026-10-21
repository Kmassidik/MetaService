"""Starts the pretend Debian computer (fake_linux.py) for a browser test and keeps it up until it is told to stop (a line on standard input, or the end of it).
Prints one line of JSON first: its port, folder, authorized_keys file and host key fingerprint."""
import json
import sys

from contract.root_tests.fakes.fake_linux import FakeLinux, PASSWORD


def main():
    server = FakeLinux().start()
    try:
        print(json.dumps({"port": server.port, "dir": server.dir, "authorized": server.authorized, "fingerprint": server.fingerprint(), "password": PASSWORD}), flush=True)
        sys.stdin.readline()
    finally:
        server.stop()


if __name__ == "__main__":
    main()
