"""A stand-in for the MikroTik binary API (plain). Supports the new login and the old challenge login, and the two print commands."""
import hashlib
import socketserver
import threading

USER, PASSWORD = "readonly", "not-a-real-password"
CHALLENGE = bytes(range(16))


def encode_length(n):
    if n < 0x80:
        return bytes([n])
    if n < 0x4000:
        return (n | 0x8000).to_bytes(2, "big")
    if n < 0x200000:
        return (n | 0xC00000).to_bytes(3, "big")
    return (n | 0xE0000000).to_bytes(4, "big")


def sentence(words):
    return b"".join(encode_length(len(w.encode())) + w.encode() for w in words) + b"\x00"


def read_sentence(rfile):
    words = []
    while True:
        first = rfile.read(1)
        if not first:
            return None
        b = first[0]
        if b < 0x80:
            length = b
        elif b < 0xC0:
            length = ((b & 0x3F) << 8) | rfile.read(1)[0]
        elif b < 0xE0:
            length = ((b & 0x1F) << 16) | int.from_bytes(rfile.read(2), "big")
        else:
            length = ((b & 0x0F) << 24) | int.from_bytes(rfile.read(3), "big")
        if length == 0:
            return words
        words.append(rfile.read(length).decode())


def make_router(host, prefix, old_login=False, hostile_name="<img src=x onerror=alert(1)>\x1b[31mevil"):
    leases = [
        {"address": f"{prefix}.50", "mac-address": "AA:BB:CC:00:00:50", "host-name": "printer", "status": "bound", "disabled": "false"},
        {"address": f"{prefix}.60", "mac-address": "AA:BB:CC:00:00:60", "host-name": "dgx-spark", "status": "bound"},
        {"address": f"{prefix}.66", "mac-address": "AA:BB:CC:00:00:66", "host-name": hostile_name, "status": "bound"},
        {"address": "10.99.99.9", "mac-address": "AA:BB:CC:00:00:99", "host-name": "outside", "status": "bound"},
    ]
    arp = [{"address": f"{prefix}.1", "mac-address": "AA:BB:CC:00:00:01", "complete": "true"}]

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            if not self.login():
                return
            while True:
                words = read_sentence(self.rfile)
                if not words:
                    return
                rows = {"/ip/dhcp-server/lease/print": leases, "/ip/arp/print": arp}.get(words[0])
                if rows is None:
                    self.wfile.write(sentence(["!trap", "=message=no such command"]) + sentence(["!done"]))
                    continue
                for row in rows:
                    self.wfile.write(sentence(["!re"] + [f"={k}={v}" for k, v in row.items()]))
                self.wfile.write(sentence(["!done"]))

        def login(self):
            words = read_sentence(self.rfile)
            if old_login:
                self.wfile.write(sentence(["!done", "=ret=" + CHALLENGE.hex()]))
                words = read_sentence(self.rfile)
                expected = "=response=00" + hashlib.md5(b"\x00" + PASSWORD.encode() + CHALLENGE).hexdigest()
                ok = words and f"=name={USER}" in words and expected in words
            else:
                ok = words and f"=name={USER}" in words and f"=password={PASSWORD}" in words
            self.wfile.write(sentence(["!done"]) if ok else sentence(["!trap", "=message=invalid user name or password"]) + sentence(["!done"]))
            return ok

    server = socketserver.ThreadingTCPServer((host, 0), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
