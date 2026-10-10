"""Headers, public endpoints, and that every protected endpoint is closed without credentials."""
import socket

from contract import spec
from contract.root_tests.support import Browser, expect, running, RunningRoot
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


def check_operator_endpoints_refuse_a_foreign_host_name():
    """DNS rebinding: a page on another site that points its own name at this machine sends its own name as the Host."""
    with running() as root:
        browser = Browser(root)
        for method, path in OPERATOR_ENDPOINTS:
            for host in ("evil.example", f"evil.example:{root.port}", f"localhost:{root.port + 1}", f"127.0.0.1:{root.port}"):
                reply = browser.request(method, path, body={} if method == "POST" else None, headers={"Host": host})
                expect(reply.status == 403, f"{method} {path} with Host {host} gave {reply.status}")
                expect_schema("Error", reply.body, f"{method} {path}")
        expect(browser.request("GET", "/api/machines").status == 200, "the right Host is refused")


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


def check_each_listener_serves_only_its_own_routes():
    with running() as root:
        browser = Browser(root)
        on_operator = lambda method, path, **kw: browser.request(method, path, headers={"Host": f"localhost:{root.port}"}, **kw)
        for method, path in (("POST", "/v1/agents/enroll"), ("POST", "/v1/agents/heartbeat"), ("GET", "/v1/bundles/0.1.0/noarch"), ("POST", "/v1/brain/chat"), ("POST", "/v1/brain/capability")):
            reply = _on_port(root.port, method, path)
            expect(reply == 404, f"the operator listener answered {method} {path} with {reply}")
        for method, path in (("GET", "/api/machines"), ("GET", "/api/session"), ("GET", "/api/brain"), ("GET", "/api/bundles"), ("POST", "/api/workloads"), ("GET", "/")):
            reply = _on_port(root.agent_port, method, path)
            expect(reply == 404, f"the Agent listener answered {method} {path} with {reply}")
        expect(on_operator("GET", "/health").body == {"status": "ok"} and _on_port(root.agent_port, "GET", "/health") == 200, "both listeners answer /health")


def _on_port(port, method, path):
    import http.client
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    connection.request(method, path, body=b"{}" if method == "POST" else None, headers={"Content-Type": "application/json"})
    status = connection.getresponse().status
    connection.close()
    return status


def check_the_operator_listener_refuses_to_leave_this_machine():
    for flag, value in (("--bind", "0.0.0.0"), ("--bind", "192.168.100.40"), ("--bind", "::")):
        root = RunningRoot(extra_args=["--ui-dir", "/nonexistent-ui", flag, value])
        try:
            root.start()
        except AssertionError:
            code, text = root.exit_text()
            expect(code != 0 and "operator listener" in text, f"{flag} {value}: wrong refusal {code} {text[:120]}")
            continue
        finally:
            root.stop()
        raise AssertionError(f"the Root started with the operator listener on {value}")


def check_a_root_whose_port_is_taken_exits_with_an_error_instead_of_running_half_alive():
    """Once the Agent port was taken, the Root kept the operator port open and never exited, so nothing noticed anything was wrong."""
    with socket.socket() as taken:
        taken.bind(("127.0.0.1", 0))
        taken.listen()
        root = RunningRoot()
        root.agent_port = taken.getsockname()[1]
        try:
            root.start()
        except Exception as problem:
            said = root.early_exit[1].lower()
            expect("exited early" in str(problem) and "in use" in said, f"the Root stopped, but not for the right reason: {said[-300:]}")
            return
        finally:
            root.stop()
        raise AssertionError("the Root kept running with its Agent port taken")


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


CHECKS = [check_a_root_whose_port_is_taken_exits_with_an_error_instead_of_running_half_alive, check_ui_files_are_served_with_a_strict_page_policy, 
    check_health_is_public_and_minimal, check_security_headers_on_every_reply, check_unknown_paths_and_methods_are_clean_404s,
    check_operator_endpoints_refuse_a_foreign_host_name, check_agent_endpoints_need_a_token, check_no_cors_headers_ever,
    check_errors_reveal_nothing_inside, check_each_listener_serves_only_its_own_routes,
    check_the_operator_listener_refuses_to_leave_this_machine, check_root_refuses_an_env_file_others_can_read,
]
