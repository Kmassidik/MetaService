"""The AI proxy on the Root: settings, the panel status and test button, and the doors that refuse. The full chat round trip is in system_tests."""
from contextlib import contextmanager

from contract.root_tests.fakes.fake_ai import make_ai
from contract.root_tests.support import REPO, Browser, RunningRoot, expect, running

KEY = "sk-test-not-a-real-key-1234567890"
MODEL = "fake-model"


@contextmanager
def brain_root(extra="", ai=None, configured=True):
    ai = ai or make_ai(KEY)
    settings = f"AI_BASE_URL={ai.base_url}\nAI_API_KEY={KEY}\nAI_DEFAULT_MODEL={MODEL}\n" if configured else ""
    env = f"{settings}{extra}"
    with running(env_text=env) as root:
        operator = Browser(root)
        yield root, operator, ai
    ai.shutdown()


def refused_at_start(env_lines):
    root = RunningRoot(env_text=env_lines)
    try:
        root.start()
    except AssertionError:
        return root.exit_text()[1]
    finally:
        root.stop()
    raise AssertionError("the Root started with bad AI settings")


def check_the_panel_status_says_configured_and_never_shows_the_key():
    with brain_root() as (root, operator, ai):
        reply = operator.request("GET", "/api/brain")
        expect(reply.status == 200 and reply.body["configured"] is True and reply.body["model"] == MODEL, f"status: {reply.status} {reply.body}")
        expect(reply.body["host"] == "127.0.0.1" and reply.body["usage"] == [], f"status body: {reply.body}")
        every_reply = reply.raw + operator.request("GET", "/api/session").raw + operator.request("GET", "/api/audit").raw
        expect(KEY.encode() not in every_reply, "the AI key is in a reply")


def check_without_settings_the_status_says_not_configured_and_test_and_capability_are_refused():
    with brain_root(configured=False) as (root, operator, ai):
        status = operator.request("GET", "/api/brain").body
        expect(status["configured"] is False and status.get("model") is None and status.get("host") is None, f"status: {status}")
        reply = operator.write("POST", "/api/brain/test")
        expect(reply.status == 503 and reply.body["error"]["code"] == "not_configured", f"test: {reply.status} {reply.body}")
        expect(ai.calls == [], "the provider was called although nothing is configured")


def check_the_test_button_makes_one_tiny_request_with_the_token_limit_and_is_audited():
    with brain_root(extra="AI_MAX_TOKENS=300\n") as (root, operator, ai):
        reply = operator.write("POST", "/api/brain/test")
        expect(reply.status == 200 and reply.body == {"ok": True}, f"test: {reply.status} {reply.body}")
        expect(len(ai.calls) == 1, f"calls: {ai.calls}")
        call = ai.calls[0]
        expect(call["authorization"] == f"Bearer {KEY}" and call["body"]["model"] == MODEL, f"call: {call}")
        expect(call["body"]["max_tokens"] <= 8 and call["body"]["stream"] is False and len(call["body"]["messages"]) == 1, f"body: {call['body']}")
        actions = [e["action"] for e in operator.request("GET", "/api/audit").body["entries"]]
        expect("brain.test" in actions, f"audit: {actions[:8]}")


def check_the_test_button_needs_the_host_the_csrf_token_and_the_right_origin():
    with brain_root() as (root, operator, ai):
        expect(operator.request("GET", "/api/brain", headers={"Host": "evil.example"}).status == 403, "status for a foreign Host")
        expect(operator.write("POST", "/api/brain/test", headers={"Host": "evil.example"}).status == 403, "test for a foreign Host")
        expect(operator.request("POST", "/api/brain/test").status == 403, "test without the CSRF token")
        expect(operator.write("POST", "/api/brain/test", origin="http://evil.example").status == 403, "test from another origin")
        expect(ai.calls == [], "the provider was called by a refused request")


def check_a_provider_failure_is_reported_without_its_details():
    with brain_root(ai=make_ai("some-other-key")) as (root, operator, ai):
        reply = operator.write("POST", "/api/brain/test")
        expect(reply.status == 502 and reply.body["error"]["code"] == "upstream_failed", f"test: {reply.status} {reply.body}")
        expect(b"some-other-key" not in reply.raw and b"bad key" not in reply.raw and KEY.encode() not in reply.raw, "provider detail leaked")


def check_unknown_chat_keys_and_capabilities_are_refused_before_any_provider_call():
    with brain_root() as (root, operator, ai):
        anonymous = Browser(root)
        for path, token in [("/v1/brain/capability", "k" * 43), ("/v1/brain/chat", "cap-never-issued")]:
            reply = anonymous.request("POST", path, {"message": "hi"} if "chat" in path else None, headers={"Authorization": f"Bearer {token}"}, origin=None)
            expect(reply.status == 401, f"{path} with a made-up token gave {reply.status}")
        expect(anonymous.request("POST", "/v1/brain/chat", {"message": "hi"}, origin=None).status == 401, "no token at all")
        expect(ai.calls == [], "the provider was called for an unknown capability")


def check_repeated_wrong_tokens_lock_the_address_out():
    with brain_root(extra="") as (root, operator, ai):
        anonymous = Browser(root)
        codes = [anonymous.request("POST", "/v1/brain/capability", headers={"Authorization": f"Bearer {'x' * 40}{n}"}, origin=None).status for n in range(14)]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"codes: {codes}")


def check_half_set_or_unsafe_settings_stop_the_start():
    key_only = refused_at_start(f"AI_API_KEY={KEY}\n")
    expect("must all be set" in key_only and KEY not in key_only, f"half set: {key_only[:200]}")
    for url in ["file:///etc/passwd", "http://example.com/v1", "https://user:pw@example.com/v1", "https://example.com/v1?x=1", "nonsense"]:
        text = refused_at_start(f"AI_BASE_URL={url}\nAI_API_KEY={KEY}\nAI_DEFAULT_MODEL={MODEL}\n")
        expect("AI_BASE_URL" in text and KEY not in text, f"{url}: {text[:200]}")
    for line in ["AI_MAX_TOKENS=0", "AI_MAX_TOKENS=99999", "AI_MAX_TOKENS=abc", "AI_CAPABILITY_SECONDS=5", "AI_CAPABILITY_SECONDS=999999"]:
        expect(line.split("=")[0] in refused_at_start(line + "\n"), f"{line} was accepted")


def check_the_example_env_file_can_be_copied_as_it_is():
    example = (REPO / "root.env.example").read_text()
    with running(env_text=example) as root:
        expect(Browser(root).request("GET", "/health").status == 200, "the Root did not start from the example file")
        expect(KEY not in example and "=sk-" not in example, "the example file holds a key")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
