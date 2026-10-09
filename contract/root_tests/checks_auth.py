"""The operator account, as in the MAAS panel: first-run setup, username and password sign-in, lockout, session cookie, CSRF, Origin, logout."""
import os

from contract.root_tests.support import ADMIN_PASSWORD, ADMIN_USER, Browser, expect, running
from contract.tests.support import expect_schema


def fresh(root):
    return Browser(root, auto_login=False)


def setup_body(**changes):
    return {"username": ADMIN_USER, "password": ADMIN_PASSWORD, "confirm": ADMIN_PASSWORD, **changes}


def check_the_first_visit_creates_the_admin_login_and_signs_in_with_a_safe_cookie():
    with running() as root:
        browser = fresh(root)
        expect(browser.request("GET", "/api/auth/status").body == {"configured": False, "signed_in": False}, "a new Root should ask for setup")
        reply = browser.request("POST", "/api/auth/setup", setup_body())
        expect(reply.status == 201 and reply.body["username"] == ADMIN_USER and len(reply.body["csrf_token"]) >= 43, f"setup: {reply.status} {reply.body}")
        for flag in ("HttpOnly", "SameSite=Strict", "Path=/", "Max-Age="):
            expect(flag in reply.cookies[0], f"session cookie lacks {flag}: {reply.cookies[0]}")
        expect(browser.request("GET", "/api/auth/status").body == {"configured": True, "signed_in": True}, "status after setup")
        expect(browser.request("GET", "/api/session").body["username"] == ADMIN_USER, "the session does not know its user")


def check_setup_refuses_bad_input_and_cannot_run_twice():
    with running() as root:
        browser = fresh(root)
        bad = [setup_body(confirm="different one"), setup_body(password="short", confirm="short"), setup_body(username="a"), setup_body(username="has space"),
               setup_body(username="x" * 33), {"username": ADMIN_USER, "password": ADMIN_PASSWORD}, setup_body(extra=1), setup_body(password="x" * 201, confirm="x" * 201)]
        for body in bad:
            reply = browser.request("POST", "/api/auth/setup", body)
            expect(reply.status == 400 and not reply.cookies, f"{str(body)[:50]}: {reply.status}")
        expect(browser.request("POST", "/api/auth/setup", setup_body()).status == 201, "a good setup was refused")
        other = fresh(root)
        again = other.request("POST", "/api/auth/setup", setup_body(username="intruder", password="another password", confirm="another password"))
        expect(again.status == 409 and not again.cookies, f"a second setup gave {again.status}")
        expect(fresh(root).request("POST", "/api/auth/login", {"username": "intruder", "password": "another password"}).status == 401, "the account was replaced")
        expect(fresh(root).request("POST", "/api/auth/login", {"username": ADMIN_USER, "password": ADMIN_PASSWORD}).status == 200, "the real account stopped working")


def check_wrong_logins_are_refused_the_same_way_and_the_password_is_never_stored():
    with running() as root:
        fresh(root).request("POST", "/api/auth/setup", setup_body())
        replies = [fresh(root).request("POST", "/api/auth/login", body) for body in (
            {"username": ADMIN_USER, "password": "wrong password"}, {"username": "nobody", "password": ADMIN_PASSWORD}, {"username": ADMIN_USER.upper(), "password": ADMIN_PASSWORD})]
        expect(all(r.status == 401 and not r.cookies for r in replies), f"statuses: {[r.status for r in replies]}")
        expect(len({r.raw for r in replies}) == 1, "a wrong user and a wrong password look different")
        raw = b"".join(open(os.path.join(root.dir, n), "rb").read() for n in os.listdir(root.dir) if n.startswith("root.sqlite3"))
        expect(ADMIN_PASSWORD.encode() not in raw, "the password is in the database in clear")


def check_too_many_wrong_passwords_lock_the_address_out():
    with running() as root:
        fresh(root).request("POST", "/api/auth/setup", setup_body())
        attacker = fresh(root)
        codes = [attacker.request("POST", "/api/auth/login", {"username": ADMIN_USER, "password": f"guess {n}"}).status for n in range(12)]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"codes: {codes}")
        expect(attacker.request("POST", "/api/auth/login", {"username": ADMIN_USER, "password": ADMIN_PASSWORD}).status == 429, "the lockout let the right password through")


def check_login_and_setup_need_the_exact_origin_and_host():
    with running() as root:
        browser = fresh(root)
        for origin in (None, "http://evil.example", root.base + ".evil.com", "null"):
            expect(browser.request("POST", "/api/auth/setup", setup_body(), origin=origin).status == 403, f"setup with Origin {origin}")
        expect(browser.request("POST", "/api/auth/setup", setup_body(), headers={"Host": "evil.example"}).status == 403, "setup for a foreign Host")
        expect(browser.request("GET", "/api/auth/status", headers={"Host": "evil.example"}).status == 403, "status for a foreign Host")
        expect(browser.request("POST", "/api/auth/setup", setup_body()).status == 201, "the real setup was refused")


def check_operator_endpoints_need_a_session():
    with running() as root:
        fresh(root).request("POST", "/api/auth/setup", setup_body())
        browser = fresh(root)
        for method, path in (("GET", "/api/session"), ("GET", "/api/machines"), ("GET", "/api/audit"), ("GET", "/api/bundles"), ("GET", "/api/brain"),
                             ("POST", "/api/enrollments"), ("POST", "/api/workloads"), ("POST", "/api/scans"), ("DELETE", "/api/machines/mini")):
            reply = browser.request(method, path, body={} if method == "POST" else None)
            expect(reply.status == 401, f"{method} {path} without a session gave {reply.status}")
            expect_schema("Error", reply.body, f"{method} {path}")


def check_forged_and_repeated_session_cookies_fail():
    with running() as root:
        browser = fresh(root)
        browser.request("POST", "/api/auth/setup", setup_body())
        real = browser.cookies["ms_session"]
        for cookie in ("ms_session=forged", "ms_session=", f"ms_session={real}x", f"ms_session={real}; ms_session=forged"):
            reply = fresh(root).request("GET", "/api/session", headers={"Cookie": cookie}, cookies=False)
            expect(reply.status == 401, f"cookie {cookie[:30]!r} gave {reply.status}")


def check_writes_need_csrf_and_the_exact_origin():
    with running() as root:
        browser = Browser(root)
        token = browser.csrf()
        body = {"name": "mini"}
        cases = [
            ("no CSRF token", {}, "default"), ("wrong CSRF token", {"X-CSRF-Token": "x" * 43}, "default"),
            ("no Origin", {"X-CSRF-Token": token}, None), ("foreign Origin", {"X-CSRF-Token": token}, "http://evil.example"),
            ("prefix Origin", {"X-CSRF-Token": token}, root.base + ".evil.com"), ("null Origin", {"X-CSRF-Token": token}, "null"),
        ]
        for label, headers, origin in cases:
            reply = browser.request("POST", "/api/enrollments", body, headers=headers, origin=origin)
            expect(reply.status == 403, f"{label}: wanted 403, got {reply.status}")
            expect_schema("Error", reply.body, label)
        expect(browser.request("POST", "/api/enrollments", body, headers={"X-CSRF-Token": token}).status == 201, "a correct write was refused")


def check_a_csrf_token_from_another_session_is_useless():
    with running() as root:
        first = Browser(root)
        first.csrf()
        second = fresh(root)
        second.sign_in()
        reply = first.request("POST", "/api/enrollments", {"name": "mini"}, headers={"X-CSRF-Token": second.csrf()})
        expect(reply.status == 403, f"another session's CSRF token gave {reply.status}")


def check_logout_ends_the_session_and_needs_csrf():
    with running() as root:
        browser = Browser(root)
        stolen = dict(browser.sign_in() and browser.cookies)
        expect(browser.request("POST", "/api/auth/logout").status == 403, "a logout without CSRF was accepted")
        expect(browser.request("GET", "/api/session").status == 200, "a forged logout ended the session")
        reply = browser.write("POST", "/api/auth/logout")
        expect(reply.status == 204 and any("Max-Age=0" in c for c in reply.cookies), f"logout gave {reply.status}")
        replay = fresh(root)
        replay.cookies = stolen
        expect(replay.request("GET", "/api/session").status == 401, "the old cookie still works after logout")


def check_sign_ins_and_actions_are_audited_under_the_username():
    with running() as root:
        fresh(root).request("POST", "/api/auth/setup", setup_body())
        fresh(root).request("POST", "/api/auth/login", {"username": ADMIN_USER, "password": "wrong password"})
        browser = fresh(root)
        browser.sign_in()
        browser.write("POST", "/api/enrollments", {"name": "mini"})
        entries = browser.request("GET", "/api/audit").body["entries"]
        pairs = [(e["action"], e["actor"]) for e in entries]
        for wanted in (("auth.setup", ADMIN_USER), ("auth.login", ADMIN_USER), ("enrollment.create", ADMIN_USER)):
            expect(wanted in pairs, f"no {wanted} entry in {pairs}")
        expect(any(action == "auth.login_denied" for action, _ in pairs), f"no denied entry: {pairs}")
        expect(ADMIN_PASSWORD not in str(entries) and "wrong password" not in str(entries), "a password is in the audit log")


CHECKS = [
    check_the_first_visit_creates_the_admin_login_and_signs_in_with_a_safe_cookie, check_setup_refuses_bad_input_and_cannot_run_twice,
    check_wrong_logins_are_refused_the_same_way_and_the_password_is_never_stored, check_too_many_wrong_passwords_lock_the_address_out,
    check_login_and_setup_need_the_exact_origin_and_host, check_operator_endpoints_need_a_session, check_forged_and_repeated_session_cookies_fail,
    check_writes_need_csrf_and_the_exact_origin, check_a_csrf_token_from_another_session_is_useless, check_logout_ends_the_session_and_needs_csrf,
    check_sign_ins_and_actions_are_audited_under_the_username,
]
