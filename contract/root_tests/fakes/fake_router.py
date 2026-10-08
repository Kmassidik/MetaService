"""A stand-in for the MikroTik REST API. Needs the right Basic credentials, serves fixture leases and ARP."""
import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER, PASSWORD = "readonly", "not-a-real-password"


def make_router(host, prefix, hostile_name="<img src=x onerror=alert(1)>\x1b[31mevil"):
    leases = [
        {".id": "*1", "address": f"{prefix}.50", "mac-address": "AA:BB:CC:00:00:50", "host-name": "printer", "status": "bound", "disabled": "false"},
        {".id": "*2", "address": f"{prefix}.60", "mac-address": "AA:BB:CC:00:00:60", "host-name": "dgx-spark", "status": "bound"},
        {".id": "*3", "address": f"{prefix}.66", "mac-address": "AA:BB:CC:00:00:66", "host-name": hostile_name, "status": "bound"},
        {".id": "*4", "address": "10.99.99.9", "mac-address": "AA:BB:CC:00:00:99", "host-name": "outside", "status": "bound"},
    ]
    arp = [{"address": f"{prefix}.1", "mac-address": "AA:BB:CC:00:00:01", "complete": "true"}]
    expected = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            return

        def do_GET(self):
            if self.headers.get("Authorization") != expected:
                self.send_response(401)
                self.end_headers()
                return
            data = {"/rest/ip/dhcp-server/lease": leases, "/rest/ip/arp": arp}.get(self.path)
            self.send_response(200 if data is not None else 404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data if data is not None else {}).encode())

    server = ThreadingHTTPServer((host, 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
