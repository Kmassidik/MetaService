"""Operator sessions: allow-list, cookie flags, CSRF, Origin, logout."""
from contract.root_tests.support import ALLOWED_EMAIL, Browser, expect, running
from contract.tests.support import expect_schema


def check_allowed_email_gets_a_safe_cookie():
    with running() as root:
        browser = Browser(root)
        reply = browser.sign_in()
        cookie = reply.cookies[0]
        for flag in ("HttpOnly", "SameSite=Strict", "Path=/", "Max-Age="):
            expect(flag in cookie, f"session cookie lacks {flag}: {cookie}")
        expect(reply.header("Location") == "/", "sign-in does not go back to the app")
        session = browser.request("GET", "/api/session")
        expect(session.status == 200 and session.body["email"] == ALLOWED_EMAIL and len(session.body["csrf_token"]) >= 43, f"bad session reply {session.body}")


def check_email_not_on_the_list_is_refused():
    with running() as root:
        for email in ("stranger@example.com", "kurnia@example.com.evil.com", "x@example.com", "kurnia+tag@example.com", ""):
            browser = Browser(root)
            reply = browser.request("POST", "/auth/fake", {"email": email})
            expect(reply.status in (400, 403) and not reply.cookies, f"{email!r}: status {reply.status}, cookies {reply.cookies}")
            expect(browser.request("GET", "/api/machines").status == 401, f"{email!r} got in")


def check_email_match_ignores_case_only():
    with running() as root:
        reply = Browser(root).request("POST", "/auth/fake", {"email": "KURNIA@Example.COM"})
        expect(reply.status == 302, f"upper-case spelling of an allowed email gave {reply.status}")


def check_forged_and_repeated_session_cookies_fail():
    with running() as root:
        browser = Browser(root)
        browser.sign_in()
        real = browser.cookies["ms_session"]
        for cookie in ("ms_session=forged", "ms_session=", f"ms_session={real}x", f"ms_session={real}; ms_session=forged"):
            reply = Browser(root).request("GET", "/api/session", headers={"Cookie": cookie}, cookies=False)
            expect(reply.status == 401, f"cookie {cookie[:30]!r} gave {reply.status}")


def check_writes_need_csrf_and_the_exact_origin():
    with running() as root:
        browser = Browser(root)
        browser.sign_in()
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
        ok = browser.request("POST", "/api/enrollments", body, headers={"X-CSRF-Token": token})
        expect(ok.status == 201, f"a correct write gave {ok.status}")


def check_a_csrf_token_from_another_session_is_useless():
    with running() as root:
        first, second = Browser(root), Browser(root)
        first.sign_in()
        second.sign_in()
        reply = first.request("POST", "/api/enrollments", {"name": "mini"}, headers={"X-CSRF-Token": second.csrf()})
        expect(reply.status == 403, f"another session's CSRF token gave {reply.status}")


def check_logout_ends_the_session():
    with running() as root:
        browser = Browser(root)
        browser.sign_in()
        stolen = dict(browser.cookies)
        reply = browser.write("POST", "/auth/logout")
        expect(reply.status == 204, f"logout gave {reply.status}")
        expect(any("Max-Age=0" in c for c in reply.cookies), "logout does not clear the cookie")
        replay = Browser(root)
        replay.cookies = stolen
        expect(replay.request("GET", "/api/session").status == 401, "the old cookie still works after logout")


def check_logout_needs_csrf_too():
    with running() as root:
        browser = Browser(root)
        browser.sign_in()
        reply = browser.request("POST", "/auth/logout")
        expect(reply.status == 403, f"logout without CSRF gave {reply.status}")
        expect(browser.request("GET", "/api/session").status == 200, "a forged logout ended the session")


def check_sign_ins_are_audited():
    with running() as root:
        Browser(root).request("POST", "/auth/fake", {"email": "stranger@example.com"})
        browser = Browser(root)
        browser.sign_in()
        actions = [(entry["action"], entry["actor"]) for entry in browser.request("GET", "/api/audit").body["entries"]]
        expect(("auth.login", ALLOWED_EMAIL) in actions, f"no login entry: {actions}")
        expect(any(action == "auth.login_denied" for action, _ in actions), f"no denied entry: {actions}")


CHECKS = [
    check_allowed_email_gets_a_safe_cookie, check_email_not_on_the_list_is_refused, check_email_match_ignores_case_only,
    check_forged_and_repeated_session_cookies_fail, check_writes_need_csrf_and_the_exact_origin,
    check_a_csrf_token_from_another_session_is_useless, check_logout_ends_the_session, check_logout_needs_csrf_too,
    check_sign_ins_are_audited,
]
