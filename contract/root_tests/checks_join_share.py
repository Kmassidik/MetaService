"""Share a PC through the parent: a real Root and a fake hub (fakes/fake_hub.py). The panel's session and CSRF rules, the allow-list of method and path,
the hub's status and JSON passed through unchanged, the two answers of the proxy itself (not configured, hub unreachable), the admin key sent only
to the hub (and never in any response or the audit trail), the 16 KiB body limit, and the settings at start."""
import json
import os
from contextlib import contextmanager

from contract.root_tests.fakes.fake_hub import make_hub
from contract.root_tests.support import REPO, Browser, RunningRoot, _free_port, expect, running

KEY = "hub-key-0123456789abcdef-not-real"
SECRET_CODE = "424242"
MAX_BODY = 16 * 1024


@contextmanager
def share_root(hub=None, key_text=KEY + "\n", url=None, configured=True):
    hub = hub or make_hub(KEY)
    key_file = None
    root = RunningRoot(env_text="")
    key_file = os.path.join(root.dir, "admin.key")
    if key_text is not None:
        with open(key_file, "w") as handle:
            handle.write(key_text)
    settings = f"JOIN_SHARE_ADMIN_URL={url or hub.base_url}\nJOIN_SHARE_ADMIN_KEY_FILE={key_file}\n" if configured else ""
    open(root.env_file, "w").write(settings)
    root.start()
    try:
        yield root, Browser(root), hub
    finally:
        root.stop()
        hub.shutdown()


def unreachable_url():
    return f"http://127.0.0.1:{_free_port()}"


def check_share_without_settings_everything_but_status_says_not_configured():
    with share_root(configured=False) as (root, operator, hub):
        status = operator.request("GET", "/api/join-share/status")
        expect(status.status == 200 and status.body == {"configured": False, "reachable": False}, f"status: {status.status} {status.body}")
        for path in ["supported", "pending", "peers"]:
            reply = operator.request("GET", f"/api/join-share/{path}")
            expect(reply.status == 404 and reply.body == {"error": "not_configured"}, f"{path}: {reply.status} {reply.raw}")
        reply = operator.write("POST", "/api/join-share/links", {"os": "mac", "cpu": "arm64"})
        expect(reply.status == 404 and reply.body == {"error": "not_configured"}, f"links: {reply.status} {reply.raw}")
        expect(hub.calls == [], f"the hub was called: {hub.calls}")


def check_share_status_is_answered_by_the_parent_and_says_reachable():
    with share_root() as (root, operator, hub):
        reply = operator.request("GET", "/api/join-share/status")
        expect(reply.status == 200 and reply.body == {"configured": True, "reachable": True}, f"status: {reply.status} {reply.raw}")
        expect([c["path"] for c in hub.calls] == ["/admin/supported"], f"hub calls: {hub.calls}")


def check_share_hub_down_gives_502_hub_unreachable_and_status_says_not_reachable():
    with share_root(url=unreachable_url()) as (root, operator, hub):
        status = operator.request("GET", "/api/join-share/status")
        expect(status.status == 200 and status.body == {"configured": True, "reachable": False}, f"status: {status.status} {status.raw}")
        reply = operator.request("GET", "/api/join-share/pending")
        expect(reply.status == 502 and reply.body == {"error": "hub_unreachable"}, f"pending: {reply.status} {reply.raw}")
        reply = operator.write("DELETE", "/api/join-share/peers/box")
        expect(reply.status == 502 and reply.body == {"error": "hub_unreachable"}, f"remove: {reply.status} {reply.raw}")
        actions = [e["action"] for e in operator.request("GET", "/api/audit").body["entries"]]
        expect("join_share.remove" not in actions, f"a call that never reached the hub was audited: {actions}")


def check_share_a_missing_or_empty_key_file_is_hub_unreachable_and_leaks_nothing():
    for text in (None, "\n"):
        with share_root(key_text=text) as (root, operator, hub):
            reply = operator.request("GET", "/api/join-share/peers")
            expect(reply.status == 502 and reply.body == {"error": "hub_unreachable"}, f"key {text!r}: {reply.status} {reply.raw}")
            expect(hub.calls == [], f"the hub was called without a key: {hub.calls}")


def check_share_the_allow_list_maps_each_route_and_everything_else_is_404():
    with share_root() as (root, operator, hub):
        expected = [("GET", "supported", "/admin/supported", False), ("GET", "pending", "/admin/pending", False), ("GET", "peers", "/admin/peers", False),
                    ("POST", "links", "/admin/links", True), ("POST", "pending/p-1/approve", "/admin/pending/p-1/approve", True),
                    ("POST", "pending/p-1/refuse", "/admin/pending/p-1/refuse", True), ("DELETE", "peers/my-mac.local", "/admin/peers/my-mac.local", True)]
        for method, path, hub_path, is_write in expected:
            before = len(hub.calls)
            send = operator.write if is_write else operator.request
            reply = send(method, f"/api/join-share/{path}", {"os": "mac", "cpu": "arm64"} if method == "POST" else None)
            expect(reply.status == 200, f"{method} {path}: {reply.status} {reply.raw}")
            expect(len(hub.calls) == before + 1 and hub.calls[-1]["method"] == method and hub.calls[-1]["path"] == hub_path, f"{method} {path} reached {hub.calls[before:]}")
        before = len(hub.calls)
        refused = [("POST", "status"), ("GET", "links"), ("PUT", "links"), ("GET", "pending/p-1/approve"), ("DELETE", "pending/p-1"), ("GET", "peers/box"),
                   ("GET", "peers/"), ("GET", "admin/peers"), ("GET", ""), ("DELETE", "peers/.."), ("DELETE", "peers/a%2Fb"), ("DELETE", "peers/" + "a" * 65),
                   ("POST", "pending/a%20b/approve"), ("POST", "pending/%2e%2e/approve")]
        for method, path in refused:
            send = operator.request if method == "GET" else operator.write
            reply = send(method, f"/api/join-share/{path}")
            expect(reply.status == 404, f"{method} /api/join-share/{path} gave {reply.status}: {reply.raw[:120]}")
        expect(len(hub.calls) == before, f"a refused path reached the hub: {hub.calls[before:]}")


def check_share_no_session_gives_the_usual_refusal_and_never_reaches_the_hub():
    with share_root() as (root, operator, hub):
        stranger = Browser(root, auto_login=False)
        for method, path in [("GET", "status"), ("GET", "pending"), ("POST", "links"), ("DELETE", "peers/box")]:
            reply = stranger.request(method, f"/api/join-share/{path}")
            expect(reply.status == 401 and reply.body["error"]["code"] == "unauthorized", f"{method} {path}: {reply.status} {reply.raw[:120]}")
        expect(operator.request("GET", "/api/join-share/pending", headers={"Host": "evil.example"}).status == 403, "a foreign Host was served")
        expect(hub.calls == [], f"the hub was called: {hub.calls}")


def check_share_a_write_needs_the_csrf_token_and_the_origin():
    with share_root() as (root, operator, hub):
        operator.csrf()
        body = {"os": "mac", "cpu": "arm64"}
        for method, path in [("POST", "links"), ("POST", "pending/p-1/approve"), ("POST", "pending/p-1/refuse"), ("DELETE", "peers/box")]:
            plain = operator.request(method, f"/api/join-share/{path}", body)
            expect(plain.status == 403, f"{method} {path} without a CSRF token gave {plain.status}")
            wrong = operator.request(method, f"/api/join-share/{path}", body, headers={"X-CSRF-Token": "wrong"})
            expect(wrong.status == 403, f"{method} {path} with a wrong token gave {wrong.status}")
            foreign = operator.write(method, f"/api/join-share/{path}", body, origin="http://evil.example")
            expect(foreign.status == 403, f"{method} {path} from a foreign origin gave {foreign.status}")
        expect(hub.calls == [], f"a refused write reached the hub: {hub.calls}")


def check_share_the_hub_status_and_body_are_passed_through_and_the_key_header_is_sent():
    with share_root() as (root, operator, hub):
        wrong = operator.write("POST", "/api/join-share/pending/wrong/approve", {"code": "000000", "name": "box"})
        expect(wrong.status == 403 and wrong.body == {"error": "wrong_code", "tries_left": 2}, f"wrong code: {wrong.status} {wrong.raw}")
        taken = operator.write("DELETE", "/api/join-share/peers/taken")
        expect(taken.status == 409 and taken.body == {"error": "name_taken"}, f"taken: {taken.status} {taken.raw}")
        supported = operator.request("GET", "/api/join-share/supported")
        expect(supported.status == 200 and supported.body[0]["os"] == "mac", f"supported: {supported.status} {supported.raw}")
        sent = {"os": "mac", "cpu": "arm64"}
        link = operator.write("POST", "/api/join-share/links", sent)
        expect(link.status == 200, f"links: {link.status} {link.raw}")
        call = hub.calls[-1]
        expect(json.loads(call["body"]) == sent and call["content_type"] == "application/json", f"hub got {call}")
        expect(all(c["key"] == KEY for c in hub.calls), f"key headers: {[c['key'] for c in hub.calls]}")
        approve = next(c for c in hub.calls if c["path"].endswith("/wrong/approve"))
        expect(json.loads(approve["body"]) == {"code": "000000", "name": "box"}, f"approve body: {approve['body']}")


def check_share_the_key_is_never_in_a_response_and_a_reply_that_holds_it_is_not_passed_on():
    with share_root() as (root, operator, hub):
        replies = [operator.request("GET", "/api/join-share/status"), operator.request("GET", "/api/join-share/peers"),
                   operator.write("POST", "/api/join-share/pending/leak/approve", {"code": SECRET_CODE, "name": "box"}),
                   operator.write("POST", "/api/join-share/pending/html/approve", {"code": SECRET_CODE, "name": "box"})]
        leak, html = replies[2], replies[3]
        expect(leak.status == 502 and leak.body == {"error": "hub_unreachable"}, f"leak: {leak.status} {leak.raw}")
        expect(html.status == 502 and html.body == {"error": "hub_unreachable"}, f"html: {html.status} {html.raw}")
        for reply in replies:
            expect(KEY.encode() not in reply.raw and not any(KEY in value for _, value in reply.headers), f"the key is in a response: {reply.raw[:200]}")
        wrong_method = operator.write("POST", "/api/join-share/status")
        expect(KEY.encode() not in wrong_method.raw, "the key is in a refusal")


def check_share_writes_are_audited_with_operator_and_target_but_never_the_code_or_the_key():
    with share_root() as (root, operator, hub):
        operator.write("POST", "/api/join-share/links", {"os": "linux", "cpu": "x86_64"})
        operator.write("POST", "/api/join-share/pending/p-9/approve", {"code": SECRET_CODE, "name": "box"})
        operator.write("POST", "/api/join-share/pending/wrong/approve", {"code": SECRET_CODE, "name": "box"})
        operator.write("POST", "/api/join-share/pending/p-8/refuse")
        operator.write("DELETE", "/api/join-share/peers/box")
        operator.request("GET", "/api/join-share/pending")
        audit = operator.request("GET", "/api/audit?limit=200")
        entries = [e for e in audit.body["entries"] if e["action"].startswith("join_share.")]
        got = sorted((e["action"], e["target"]) for e in entries)
        want = sorted([("join_share.link", "linux/x86_64"), ("join_share.approve", "p-9"), ("join_share.approve", "wrong"), ("join_share.refuse", "p-8"),
                       ("join_share.remove", "box")])
        expect(got == want, f"audit: {got}")
        expect(all(e["actor"] == "admin" for e in entries), f"actors: {[e['actor'] for e in entries]}")
        expect(SECRET_CODE.encode() not in audit.raw and KEY.encode() not in audit.raw, "the code or the key is in the audit trail")


def check_share_a_body_over_16_kib_or_not_one_json_object_is_refused_before_the_hub():
    with share_root() as (root, operator, hub):
        big = {"code": "1", "name": "x" * (MAX_BODY + 10)}
        reply = operator.write("POST", "/api/join-share/pending/p-1/approve", big)
        expect(reply.status == 413 and KEY.encode() not in reply.raw, f"big body: {reply.status} {reply.raw[:120]}")
        for raw in (b"[1,2]", b"not json", b'"text"'):
            reply = operator.write("POST", "/api/join-share/links", raw=raw)
            expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"{raw!r}: {reply.status} {reply.raw[:120]}")
        expect(hub.calls == [], f"a refused body reached the hub: {hub.calls}")


def refused_at_start(env_text):
    root = RunningRoot(env_text=env_text)
    try:
        root.start()
    except AssertionError:
        return root.exit_text()[1]
    finally:
        root.stop()
    raise AssertionError("the Root started with bad join-share settings")


def check_share_bad_or_half_set_settings_stop_the_start():
    half = refused_at_start("JOIN_SHARE_ADMIN_URL=http://127.0.0.1:9111\n")
    expect("JOIN_SHARE_ADMIN_KEY_FILE" in half, f"half set: {half[:200]}")
    for url in ["nonsense", "ftp://127.0.0.1", "http://hub.example.com:9111", "https://u:p@hub.example.com", "https://hub.example.com/admin"]:
        said = refused_at_start(f"JOIN_SHARE_ADMIN_URL={url}\nJOIN_SHARE_ADMIN_KEY_FILE=/nowhere\n")
        expect("JOIN_SHARE_ADMIN_URL" in said, f"{url}: {said[:200]}")


def check_share_the_example_env_file_still_starts_and_names_both_settings():
    example = (REPO / "control-plane" / "arm64" / ".env.example").read_text()
    expect("JOIN_SHARE_ADMIN_URL" in example and "JOIN_SHARE_ADMIN_KEY_FILE" in example, "the example file does not name both settings")
    with running(env_text=example) as root:
        expect(Browser(root).request("GET", "/api/join-share/status", headers={}).status in (200, 401), "the Root did not start from the example file")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
