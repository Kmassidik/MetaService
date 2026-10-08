"""Headers, public endpoints, and that every protected endpoint is closed without credentials."""
from contract import spec
from contract.root_tests.support import PLAIN_BINARY, Browser, expect, running, RunningRoot, ALLOWED_EMAIL
from contract.tests.support import expect_schema

OPERATOR_ENDPOINTS = [
    ("GET", "/api/session"), ("GET", "/api/machines"), ("GET", "/api/machines/mini"), ("DELETE", "/api/machines/mini"),
    ("POST", "/api/enrollments"), ("GET", "/api/audit"),
]
AGENT_ENDPOINTS = [("POST", "/v1/agents/heartbeat")]


def check_health_is_public_and_minimal():
    with running() as root:
        reply = Browser(root).request("GET", "/health")
        expect(reply.status == 200 and reply.body == {"status": "ok"}, f"health gave {reply.status} {reply.body}")


def check_security_headers_on_every_reply():
    with running() as root:
        browser = Browser(root)
        for reply in (browser.request("GET", "/health"), browser.request("GET", "/api/machines"), browser.request("GET", "/nope")):
            expect("default-src 'none'" in (reply.header("Content-Security-Policy") or ""), f"{reply.status}: weak or missing CSP")
            expect("frame-ancestors 'none'" in (reply.header("Content-Security-Policy") or ""), f"{reply.status}: frames allowed")
            expect(reply.header("X-Content-Type-Options") == "nosniff", f"{reply.status}: no nosniff")
            expect(reply.header("Cache-Control") == "no-store", f"{reply.status}: cacheable")
            expect(reply.header("Referrer-Policy") == "no-referrer", f"{reply.status}: referrer leaks")
            expect(reply.header("X-MetaService-Contract") == spec.CONTRACT_VERSION, f"{reply.status}: no contract header")
            expect((reply.header("Content-Type") or "").startswith("application/json"), f"{reply.status}: not JSON")


def check_unknown_paths_and_methods_are_clean_404s():
    with running() as root:
        browser = Browser(root)
        for method, path in (("GET", "/nope"), ("GET", "/"), ("TRACE", "/health"), ("PUT", "/api/audit"), ("POST", "/health")):
            reply = browser.request(method, path)
            expect(reply.status in (404, 405), f"{method} {path} gave {reply.status}")
            expect_schema("Error", reply.body, f"{method} {path}")


def check_operator_endpoints_need_a_session():
    with running() as root:
        browser = Browser(root)
        for method, path in OPERATOR_ENDPOINTS:
            reply = browser.request(method, path, body={} if method == "POST" else None)
            expect(reply.status == 401, f"{method} {path} without a session gave {reply.status}")
            expect_schema("Error", reply.body, f"{method} {path}")


def check_agent_endpoints_need_a_token():
    with running() as root:
        browser = Browser(root)
        for method, path in AGENT_ENDPOINTS:
            reply = browser.request(method, path, body={}, origin=None)
            expect(reply.status == 401, f"{method} {path} without a token gave {reply.status}")


def check_no_cors_headers_ever():
    with running() as root:
        reply = Browser(root).request("OPTIONS", "/api/machines", headers={"Origin": "http://evil.example"})
        expect(reply.header("Access-Control-Allow-Origin") is None, "the API answers cross-origin requests")


def check_errors_reveal_nothing_inside():
    with running() as root:
        browser = Browser(root)
        replies = [browser.request("POST", "/v1/agents/enroll", raw=b"{{{", origin=None), browser.request("GET", "/api/machines/%00"),
                   browser.request("GET", "/api/audit?limit=abc&before=x'")]
        for reply in replies:
            for leak in (b"Traceback", b"sqlite", b"/Users/", b"Swift", b"Hummingbird", b"fatal"):
                expect(leak not in reply.raw, f"an error reply leaks {leak!r}: {reply.raw[:120]!r}")


def check_release_style_build_has_no_fake_door():
    with running(binary=PLAIN_BINARY) as root:
        reply = Browser(root).request("POST", "/auth/fake", {"email": ALLOWED_EMAIL})
        expect(reply.status == 404, f"a build without FAKE_AUTH answers /auth/fake with {reply.status}")
        expect("ms_session" not in Browser(root).cookies, "a session appeared without Google")
        expect(Browser(root).request("GET", "/api/machines").status == 401, "the plain build let someone in")


def check_auth_status_tells_the_ui_whether_google_is_set_up():
    with running() as root:
        expect(Browser(root).request("GET", "/auth/status").body == {"google": False}, "status should say google is not set up")
    env = "ALLOWED_EMAILS=kurnia@example.com\nGOOGLE_CLIENT_ID=test-client\nGOOGLE_CLIENT_SECRET=test-secret\n"
    with running(env_text=env) as root:
        reply = Browser(root).request("GET", "/auth/status")
        expect(reply.body == {"google": True}, "status should say google is set up")
        expect(b"test-secret" not in reply.raw and b"test-client" not in reply.raw, "status leaks the Google settings")


def check_login_says_unavailable_until_google_is_configured():
    with running() as root:
        reply = Browser(root).request("GET", "/auth/login")
        expect(reply.status == 503, f"/auth/login without Google settings gave {reply.status}")
        expect_schema("Error", reply.body, "login unavailable")


def check_login_redirects_to_google_with_pkce_when_configured():
    env = "ALLOWED_EMAILS=kurnia@example.com\nGOOGLE_CLIENT_ID=test-client\nGOOGLE_CLIENT_SECRET=test-secret\n"
    with running(env_text=env) as root:
        reply = Browser(root).request("GET", "/auth/login")
        expect(reply.status == 302, f"/auth/login gave {reply.status}")
        location = reply.header("Location") or ""
        for needle in ("accounts.google.com", "code_challenge_method=S256", "code_challenge=", "state=", "nonce=", "response_type=code", "client_id=test-client"):
            expect(needle in location, f"login redirect lacks {needle}")
        expect("test-secret" not in location, "the client secret is in the redirect")
        cookie = reply.cookies[0]
        expect("HttpOnly" in cookie and "SameSite=Lax" in cookie, f"oauth cookie flags are weak: {cookie}")


def check_callback_without_a_started_login_is_refused():
    env = "ALLOWED_EMAILS=kurnia@example.com\nGOOGLE_CLIENT_ID=test-client\nGOOGLE_CLIENT_SECRET=test-secret\n"
    with running(env_text=env) as root:
        browser = Browser(root)
        for path in ("/auth/callback?code=abc&state=xyz", "/auth/callback", "/auth/callback?error=access_denied&state=x"):
            reply = browser.request("GET", path)
            expect(reply.status in (400, 403) and not reply.cookies, f"{path} gave {reply.status} with cookies {reply.cookies}")


def check_root_refuses_an_env_file_others_can_read():
    root = RunningRoot(env_mode=0o644)
    try:
        root.start()
    except AssertionError:
        code, text = root.exit_text()
        expect(code != 0 and "mode 600" in text, f"wrong refusal: {code} {text[:120]}")
        return
    finally:
        root.stop()
    raise AssertionError("the Root started with a world-readable env file")


def check_ui_files_are_served_with_a_strict_page_policy():
    import os, tempfile, pathlib
    ui = tempfile.mkdtemp(prefix="ms-ui-")
    pathlib.Path(ui, "assets").mkdir()
    pathlib.Path(ui, "index.html").write_text("<!doctype html><title>x</title>")
    pathlib.Path(ui, "assets", "app-abc.js").write_text("console.log(1)")
    pathlib.Path(ui, "secret.txt").write_text("nope")
    with running(extra_args=["--ui-dir", ui]) as root:
        page = Browser(root).request("GET", "/")
        expect(page.status == 200 and b"<title>x</title>" in page.raw, f"index gave {page.status}")
        policy = page.header("Content-Security-Policy") or ""
        for needle in ("script-src 'self'", "style-src 'self'", "frame-ancestors 'none'", "base-uri 'none'"):
            expect(needle in policy, f"page policy lacks {needle}")
        expect("unsafe-inline" not in policy and "unsafe-eval" not in policy, "page policy allows unsafe code")
        expect(page.header("Cache-Control") == "no-cache", "index may be cached too long")
        asset = Browser(root).request("GET", "/assets/app-abc.js")
        expect(asset.status == 200 and "immutable" in (asset.header("Cache-Control") or ""), "hashed asset is not cached long")
        expect(asset.header("Content-Type", ) .startswith("text/javascript"), "wrong script type")
        for path in ("/secret.txt", "/assets/../secret.txt", "/assets/%2e%2e/secret.txt", "/.env", "/assets/", "/assets/nope.js"):
            reply = Browser(root).request("GET", path)
            expect(reply.status == 404 and b"nope" not in reply.raw, f"{path} gave {reply.status}")


CHECKS = [check_ui_files_are_served_with_a_strict_page_policy, 
    check_health_is_public_and_minimal, check_security_headers_on_every_reply, check_unknown_paths_and_methods_are_clean_404s,
    check_operator_endpoints_need_a_session, check_agent_endpoints_need_a_token, check_no_cors_headers_ever,
    check_errors_reveal_nothing_inside, check_release_style_build_has_no_fake_door,
    check_auth_status_tells_the_ui_whether_google_is_set_up, check_login_says_unavailable_until_google_is_configured, check_login_redirects_to_google_with_pkce_when_configured,
    check_callback_without_a_started_login_is_refused, check_root_refuses_an_env_file_others_can_read,
]
