"""A panel reached from the internet (served over https through the local Cloudflare connector): it tells browsers to insist on https,
asks for a longer admin password, and counts each visitor on their own address so one attacker cannot lock the real operator out."""
import tempfile

from contract.root_tests.support import ADMIN_PASSWORD, ADMIN_USER, Browser, expect, raw_exchange, running

PUBLIC = "https://meta.example.com"
PUBLIC_HOST = "meta.example.com"
LONG_PASSWORD = "twelve chars!"  # 13 characters
ELEVEN = "eleven char"
VISITOR_HEADER = "CF-Connecting-IP"


def public_root():
    return running(extra_args=["--ui-dir", tempfile.mkdtemp(prefix="ms-no-ui-"), "--public-url", PUBLIC])


def visitor(root):
    """A browser that reaches the panel as the public name, as a request through the connector does."""
    browser = Browser(root, auto_login=False)
    original = browser.request

    def request(method, path, body=None, headers=None, **kwargs):
        sent = {"Host": PUBLIC_HOST, **(headers or {})}
        kwargs.setdefault("origin", PUBLIC if method != "GET" else None)
        return original(method, path, body, headers=sent, **kwargs)

    browser.request = request
    return browser


def setup(browser, root, password):
    return browser.request("POST", "/api/auth/setup", {"username": ADMIN_USER, "password": password, "confirm": password, "setup_token": root.setup_token()})


def check_a_public_panel_sends_hsts_and_a_private_one_does_not():
    with public_root() as root:
        reply = visitor(root).request("GET", "/api/auth/status")
        expect(reply.header("Strict-Transport-Security") == "max-age=31536000", f"HSTS on the public panel: {reply.header('Strict-Transport-Security')}")
        refusal = visitor(root).request("GET", "/api/machines")
        expect(refusal.status == 401 and refusal.header("Strict-Transport-Security"), "a refusal must carry HSTS too")
        agent = raw_exchange(root, b"GET /health HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n", listener="agent").lower()
        expect(b"200" in agent.split(b"\r\n")[0] and b"strict-transport-security" not in agent, f"the LAN Agent door must answer without HSTS: {agent[:80]!r}")
    with running() as root:
        expect(Browser(root, auto_login=False).request("GET", "/api/auth/status").header("Strict-Transport-Security") is None, "HSTS over plain http")


def check_a_public_panel_asks_for_a_twelve_character_admin_password():
    with public_root() as root:
        browser = visitor(root)
        expect(browser.request("GET", "/api/auth/status").body["min_password_length"] == 12, "the status must say 12")
        expect(setup(browser, root, ELEVEN).status == 400, "an 11-character password was accepted on a public panel")
        expect(setup(browser, root, LONG_PASSWORD).status == 201, "a 13-character password was refused")
    with running() as root:
        browser = Browser(root, auto_login=False)
        expect(browser.request("GET", "/api/auth/status").body["min_password_length"] == 8, "a private panel says 8")
        expect(setup(browser, root, "eight123").status == 201, "8 characters must still work on a private panel")


def check_each_visitor_is_locked_out_on_their_own_address_behind_the_connector():
    with public_root() as root:
        expect(setup(visitor(root), root, LONG_PASSWORD).status == 201, "setup")
        attacker = visitor(root)
        wrong = {"username": ADMIN_USER, "password": "guessing"}
        codes = [attacker.request("POST", "/api/auth/login", wrong, headers={VISITOR_HEADER: "198.51.100.7"}).status for _ in range(12)]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"the attacker's codes: {codes}")
        right = {"username": ADMIN_USER, "password": LONG_PASSWORD}
        expect(visitor(root).request("POST", "/api/auth/login", right, headers={VISITOR_HEADER: "198.51.100.7"}).status == 429, "the attacker's address is still locked")
        expect(visitor(root).request("POST", "/api/auth/login", right, headers={VISITOR_HEADER: "198.51.100.8"}).status == 200, "the real operator was locked out with the attacker")


def check_a_forged_address_header_cannot_dodge_the_lockout_on_a_private_panel():
    with running() as root:
        browser = Browser(root, auto_login=False)
        expect(browser.request("POST", "/api/auth/setup", {"username": ADMIN_USER, "password": ADMIN_PASSWORD, "confirm": ADMIN_PASSWORD, "setup_token": root.setup_token()}).status == 201, "setup")
        codes = [browser.request("POST", "/api/auth/login", {"username": ADMIN_USER, "password": "guess"}, headers={VISITOR_HEADER: f"198.51.100.{n}"}).status for n in range(12)]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"a changing header evaded the lockout: {codes}")


def check_junk_in_the_address_header_is_counted_under_the_connections_own_address():
    with public_root() as root:
        expect(setup(visitor(root), root, LONG_PASSWORD).status == 201, "setup")
        attacker = visitor(root)
        wrong = {"username": ADMIN_USER, "password": "guessing"}
        junk = ["::::", "999.1.1.1", "a, b", "x" * 200, "1.2.3", "<script>", "198.51.100.1\\r\\nX: y", "", " ", "1:2:3", "::", ":"]
        codes = [attacker.request("POST", "/api/auth/login", wrong, headers={VISITOR_HEADER: text}).status for text in junk]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"junk addresses evaded the lockout: {codes}")


CHECKS = [
    check_a_public_panel_sends_hsts_and_a_private_one_does_not, check_a_public_panel_asks_for_a_twelve_character_admin_password,
    check_each_visitor_is_locked_out_on_their_own_address_behind_the_connector, check_a_forged_address_header_cannot_dodge_the_lockout_on_a_private_panel,
    check_junk_in_the_address_header_is_counted_under_the_connections_own_address,
]
