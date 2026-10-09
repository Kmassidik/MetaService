"""A stand-in for the Root's bundle download, for testing Agents without a Root: builds real chat bundles and serves them."""
import hashlib
import http.server
import pathlib
import subprocess
import sys
import tempfile
import threading

REPO = pathlib.Path(__file__).resolve().parents[2]
VERSIONS = ["0.1.0", "0.2.0"]


class BundleSource:
    """Serves GET /v1/bundles/<version>/noarch for a machine token, and accepts heartbeats so a test Agent is not left shouting at nothing."""

    def __init__(self, machine_token, versions=VERSIONS):
        self.token, self.versions, self.hits = machine_token, versions, []
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="ms-bundles-"))
        self.sha = {}
        for version in versions:
            digest = subprocess.run([sys.executable, str(REPO / "bundles" / "chat" / "build.py"), "--version", version, "--out", str(self.dir)], capture_output=True, text=True, check=True).stdout.strip()
            self.sha[version] = digest
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"

    def _handler(self):
        source = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                return

            def _authorized(self):
                return self.headers.get("Authorization") == f"Bearer {source.token}"

            def do_GET(self):
                parts = self.path.strip("/").split("/")
                source.hits.append(self.path)
                if not self._authorized() or len(parts) != 4 or parts[:2] != ["v1", "bundles"] or parts[3] != "noarch" or parts[2] not in source.versions:
                    self.send_response(404 if self._authorized() else 401)
                    self.end_headers()
                    return
                data = (source.dir / f"metaservice-chat-{parts[2]}-noarch.tar.gz").read_bytes()
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length", "0") or 0))
                self.send_response(204)
                self.end_headers()

        return Handler

    def stop(self):
        self.server.shutdown()


def sha256_of(data):
    return hashlib.sha256(data).hexdigest()
