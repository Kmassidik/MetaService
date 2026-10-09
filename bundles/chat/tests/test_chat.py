"""Tests for the chat bundle: the service, the page, and the archive the build makes."""
import http.client
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE / "service"))
import chat  # noqa: E402

KEY = "k" * 43


class RulesTest(unittest.TestCase):
    def test_limiter_counts_per_window(self):
        now = [0.0]
        limiter = chat.Limiter(2, clock=lambda: now[0])
        self.assertEqual([limiter.allow() for _ in range(3)], [True, True, False])
        now[0] = 61
        self.assertTrue(limiter.allow())

    def test_message_must_be_exactly_one_short_text(self):
        self.assertEqual(chat.check_message('{"message": "  hi  "}'), "hi")
        for bad in ["", "{", "[]", '{"message": 5}', '{"message": ""}', '{"message": "   "}', '{"message": "x", "extra": 1}', '{"msg": "x"}',
                    json.dumps({"message": "x" * 4001})]:
            self.assertIsNone(chat.check_message(bad), bad[:30])
        self.assertEqual(len(chat.check_message(json.dumps({"message": "x" * 4000}))), 4000)

    def test_key_file_must_be_private_and_long(self):
        path = tempfile.mktemp()
        pathlib.Path(path).write_text(KEY)
        os.chmod(path, 0o644)
        with self.assertRaises(SystemExit):
            chat.read_key(path)
        os.chmod(path, 0o600)
        self.assertEqual(chat.read_key(path), KEY)
        pathlib.Path(path).write_text("short")
        with self.assertRaises(SystemExit):
            chat.read_key(path)


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), chat.make_handler(KEY, str(HERE / "web"), "9.9.9", "testhost"))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def call(self, method, path, body=None, key=KEY, headers=None):
        sent = dict(headers or {})
        if key is not None:
            sent["Authorization"] = f"Bearer {key}"
        data = body if isinstance(body, bytes) else (None if body is None else json.dumps(body).encode())
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=10)
        connection.request(method, path, body=data, headers=sent)
        response = connection.getresponse()
        raw = response.read()
        connection.close()
        return response.status, dict(response.getheaders()), raw

    def test_health_is_public_and_says_the_version(self):
        status, _, raw = self.call("GET", "/health", key=None)
        self.assertEqual((status, json.loads(raw)), (200, {"status": "ok", "version": "9.9.9"}))

    def test_the_page_is_public_and_has_a_strict_policy(self):
        for path, marker in (("/", b"<title>Chat</title>"), ("/chat.js", b"Authorization"), ("/chat.css", b"--accent")):
            status, headers, raw = self.call("GET", path, key=None)
            self.assertEqual(status, 200, path)
            self.assertIn(marker, raw)
            self.assertIn("script-src 'self'", headers["Content-Security-Policy"])
            self.assertNotIn("unsafe", headers["Content-Security-Policy"])
            self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
            self.assertEqual(headers["Cache-Control"], "no-store")

    def test_other_paths_are_404_and_nothing_is_served_from_outside_the_web_folder(self):
        for path in ("/nope", "/../service/chat.py", "/..%2fservice%2fchat.py", "/index.html", "/VERSION", "/%2e%2e/x", "/chat.js/../../x"):
            self.assertEqual(self.call("GET", path, key=None)[0], 404, path)

    def test_chat_needs_the_key(self):
        for key in (None, "", "wrong", KEY + "x", KEY[:-1]):
            status, _, raw = self.call("POST", "/api/chat", {"message": "hi"}, key=key)
            self.assertEqual(status, 401, key)
            self.assertEqual(json.loads(raw)["error"]["code"], "unauthorized")

    def test_a_good_message_is_answered_as_plain_text(self):
        status, headers, raw = self.call("POST", "/api/chat", {"message": "<img src=x onerror=alert(1)>"})
        self.assertEqual(status, 200)
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertIn("not connected yet", json.loads(raw)["reply"])

    def test_bad_messages_and_big_bodies_are_refused(self):
        for body in (b"not json", b"[]", b'{"message": 1}', b'{"message": "x", "y": 1}'):
            self.assertEqual(self.call("POST", "/api/chat", body)[0], 400, body)
        self.assertEqual(self.call("POST", "/api/chat", b'{"message": "' + b"a" * 20000 + b'"}')[0], 413)

    def test_other_methods_and_posts_elsewhere_are_404(self):
        for method, path in (("PUT", "/api/chat"), ("DELETE", "/api/chat"), ("POST", "/health"), ("POST", "/"), ("PATCH", "/")):
            self.assertEqual(self.call(method, path, {"message": "x"})[0], 404, f"{method} {path}")

    def test_errors_do_not_leak_the_key_or_internals(self):
        for status, _, raw in (self.call("POST", "/api/chat", {"message": 1}), self.call("GET", "/nope", key=None), self.call("POST", "/api/chat", {"message": "x"}, key="guess-123")):
            self.assertNotIn(KEY.encode(), raw)
            self.assertNotIn(b"guess-123", raw)
            self.assertNotIn(b"Traceback", raw)

    def test_the_rate_limit_stops_a_flood(self):
        codes = [self.call("POST", "/api/chat", {"message": "hi"})[0] for _ in range(40)]
        self.assertIn(429, codes)


class PageTest(unittest.TestCase):
    def test_the_page_never_builds_html_from_text(self):
        source = (HERE / "web" / "chat.js").read_text() + (HERE / "web" / "index.html").read_text()
        for forbidden in ("innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval(", "localStorage", "sessionStorage", "onclick=", "style="):
            self.assertNotIn(forbidden, source, forbidden)
        self.assertIn("textContent", source)


class BuildTest(unittest.TestCase):
    def build(self):
        out = subprocess.run([sys.executable, str(HERE / "build.py")], capture_output=True, text=True, check=True).stdout.strip()
        return out, HERE / "dist" / f"metaservice-chat-{(HERE / 'VERSION').read_text().strip()}-noarch.tar.gz"

    def test_the_archive_is_the_same_every_time_and_contains_only_the_bundle(self):
        first, path = self.build()
        second, _ = self.build()
        self.assertEqual(first, second, "the same sources must give the same checksum")
        with tarfile.open(path) as archive:
            members = archive.getmembers()
            names = sorted(m.name for m in members)
            self.assertEqual(names, ["VERSION", "manifest.json", "service/chat.py", "web/chat.css", "web/chat.js", "web/index.html"])
            for member in members:
                self.assertTrue(member.isfile() and not member.name.startswith("/") and ".." not in member.name, member.name)
                self.assertEqual((member.uid, member.gid), (0, 0))
            manifest = json.loads(archive.extractfile("manifest.json").read())
        self.assertEqual((manifest["name"], manifest["port"], manifest["entry"]), ("metaservice-chat", 9200, "service/chat.py"))
        self.assertEqual(manifest["version"], (HERE / "VERSION").read_text().strip())


if __name__ == "__main__":
    unittest.main()
