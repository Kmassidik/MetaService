"""The operator gate: no sign-in, so the Host, the exact Origin and the CSRF header carry the protection."""
from contract.root_tests.support import Browser, expect, running
from contract.tests.support import expect_schema


def check_the_session_reply_holds_only_the_csrf_token_and_sets_no_cookie():
    with running() as root:
        reply = Browser(root).request("GET", "/api/session")
        expect(reply.status == 200 and list(reply.body) == ["csrf_token"] and len(reply.body["csrf_token"]) >= 43, f"session reply: {reply.status} {reply.body}")
        expect(Browser(root).request("GET", "/api/session").body == reply.body, "the CSRF token changed between requests")


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
        ok = browser.request("POST", "/api/enrollments", body, headers={"X-CSRF-Token": token})
        expect(ok.status == 201, f"a correct write gave {ok.status}")


def check_a_write_to_the_wrong_host_is_refused_even_with_everything_else_right():
    with running() as root:
        browser = Browser(root)
        token = browser.csrf()
        reply = browser.request("POST", "/api/enrollments", {"name": "mini"}, headers={"X-CSRF-Token": token, "Host": "evil.example"})
        expect(reply.status == 403, f"wrong Host gave {reply.status}")
        expect(browser.request("GET", "/api/machines").body["machines"] == [], "the refused write still created an invite")


def check_a_csrf_token_from_another_root_is_useless():
    with running() as first, running() as second:
        token_of_second = Browser(second).csrf()
        reply = Browser(first).request("POST", "/api/enrollments", {"name": "mini"}, headers={"X-CSRF-Token": token_of_second})
        expect(reply.status == 403, f"another Root's CSRF token gave {reply.status}")


def check_actions_are_audited_under_the_operator_name():
    with running() as root:
        browser = Browser(root)
        browser.write("POST", "/api/enrollments", {"name": "mini"})
        entries = browser.request("GET", "/api/audit").body["entries"]
        expect(("enrollment.create", "operator") in [(e["action"], e["actor"]) for e in entries], f"audit: {entries[:3]}")


CHECKS = [
    check_the_session_reply_holds_only_the_csrf_token_and_sets_no_cookie, check_writes_need_csrf_and_the_exact_origin,
    check_a_write_to_the_wrong_host_is_refused_even_with_everything_else_right, check_a_csrf_token_from_another_root_is_useless,
    check_actions_are_audited_under_the_operator_name,
]
