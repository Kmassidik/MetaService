"""The chat's AI replies, end to end: a real chat on a real Agent asks the real Root, which asks a fake provider."""
import http.client
import json
import os
import subprocess

from contract.agent_tests.support import wait_for
from contract.root_tests.fakes.fake_ai import COMPLETION_TOKENS, PROMPT_TOKENS, make_ai
from contract.root_tests.support import Browser, expect
from contract.system_tests.checks_bundles import chat_call, install, link, pin
from contract.system_tests.support import world

KEY = "sk-test-not-a-real-key-1234567890"
V2 = "0.2.0"


def settings(ai, extra=""):
    return f"ALLOWED_EMAILS=kurnia@example.com\nAI_BASE_URL={ai.base_url}\nAI_API_KEY={KEY}\nAI_DEFAULT_MODEL=fake-model\n{extra}"


def chat_with_ai(w, machine="mini"):
    pin(w, V2)
    install(w, machine)
    url, key = link(w, machine).body["url"].split("#k=")
    return url, key


def root_post(w, path, token, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", w.root.port, timeout=10)
    connection.request("POST", path, json.dumps(body) if body is not None else b"", {"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    reply = connection.getresponse()
    raw = reply.read()
    return reply.status, (json.loads(raw) if raw else None)


def check_the_chat_answers_through_the_roots_proxy_and_the_use_is_counted():
    ai = make_ai(KEY)
    with world(with_bundles=True, root_env=settings(ai)) as w:
        w.add_machine("mini")
        url, key = chat_with_ai(w)
        status, raw = chat_call(url, key, "hello brain")
        expect(status == 200 and json.loads(raw)["reply"] == "echo: hello brain", f"chat: {status} {raw[:200]!r}")
        expect(len(ai.calls) == 1, f"provider calls: {len(ai.calls)}")
        body = ai.calls[0]["body"]
        expect(ai.calls[0]["authorization"] == f"Bearer {KEY}" and body["model"] == "fake-model" and body["max_tokens"] == 512, f"upstream: {ai.calls[0]}")
        expect(body["stream"] is False and body["messages"] == [{"role": "user", "content": "hello brain"}], f"upstream body: {body}")
        chat_call(url, key, "again")
        usage = w.operator.request("GET", "/api/brain").body["usage"]
        expect(usage == [{"machine": "mini", "requests": 2, "prompt_tokens": 2 * PROMPT_TOKENS, "completion_tokens": 2 * COMPLETION_TOKENS}], f"usage: {usage}")
    ai.shutdown()


def check_a_chat_on_the_linux_agent_uses_the_proxy_too():
    ai = make_ai(KEY)
    with world(with_bundles=True, root_env=settings(ai)) as w:
        w.add_machine("dgx", flavor="rust")
        url, key = chat_with_ai(w, "dgx")
        status, raw = chat_call(url, key, "hello from linux")
        expect(status == 200 and json.loads(raw)["reply"] == "echo: hello from linux", f"chat: {status} {raw[:200]!r}")
        expect([u["machine"] for u in w.operator.request("GET", "/api/brain").body["usage"]] == ["dgx"], "the use was not counted for the Linux machine")
    ai.shutdown()


def check_the_provider_key_is_nowhere_on_the_agent_the_chat_or_the_roots_files_except_its_env_file():
    ai = make_ai(KEY)
    with world(with_bundles=True, root_env=settings(ai)) as w:
        w.add_machine("mini")
        url, key = chat_with_ai(w)
        chat_call(url, key, "hello")
        needle = KEY.encode()
        for folder in (w.machines["mini"].agent.state, w.root.dir):
            for here, _, names in os.walk(folder):
                for name in names:
                    path = os.path.join(here, name)
                    if path == w.root.env_file or os.path.islink(path):
                        continue
                    expect(needle not in open(path, "rb").read(), f"the AI key is in {path}")
        processes = subprocess.run(["ps", "-axww", "-o", "command"], capture_output=True, text=True).stdout
        ours = [line for line in processes.splitlines() if "chat.py" in line or "metaservice-" in line]
        expect(ours and all(KEY not in line for line in ours), "the AI key is on the command line of the Root, an Agent or a chat")
        expect(KEY not in w.operator.request("GET", "/api/commands").raw.decode() + w.operator.request("GET", "/api/audit").raw.decode(), "the AI key is in an API reply")
    ai.shutdown()


def check_a_wrong_or_expired_capability_is_refused_with_no_provider_call():
    ai = make_ai(KEY)
    with world(with_bundles=True, root_env=settings(ai)) as w:
        w.add_machine("mini")
        url, key = chat_with_ai(w)
        expect(root_post(w, "/v1/brain/capability", key + "x")[0] == 401 and root_post(w, "/v1/brain/capability", "k" * 43)[0] == 401, "a wrong chat key got a capability")
        status, issued = root_post(w, "/v1/brain/capability", key)
        expect(status == 200 and issued["expires_in"] == 600 and issued["capability"] != key, f"capability: {status} {issued}")
        capability = issued["capability"]
        expect(root_post(w, "/v1/brain/chat", capability, {"message": "hi"})[0] == 200, "a fresh capability was refused")
        calls = len(ai.calls)
        expect(root_post(w, "/v1/brain/chat", capability + "x", {"message": "hi"})[0] == 401, "a wrong capability was accepted")
        expect(root_post(w, "/v1/brain/chat", key, {"message": "hi"})[0] == 401, "the chat key was accepted as a capability")
        with w.database() as db:
            db.execute("UPDATE brain_capabilities SET expires_at = 0")
        expect(root_post(w, "/v1/brain/chat", capability, {"message": "hi"})[0] == 401, "an expired capability was accepted")
        expect(len(ai.calls) == calls, "the provider was called for a refused capability")
        status, text = chat_call(url, key, "after expiry")
        expect(status == 200 and b"echo: after expiry" in text, f"the chat did not renew its capability: {status} {text[:120]!r}")
    ai.shutdown()


def check_bad_input_never_reaches_the_provider_and_a_provider_failure_is_a_clean_error():
    ai = make_ai(KEY)
    with world(with_bundles=True, root_env=settings(ai)) as w:
        w.add_machine("mini")
        url, key = chat_with_ai(w)
        capability = root_post(w, "/v1/brain/capability", key)[1]["capability"]
        for bad in [{}, {"message": ""}, {"message": "x" * 4001}, {"message": 5}, {"message": "hi", "model": "other"}, {"messages": []}]:
            status, _ = root_post(w, "/v1/brain/chat", capability, bad)
            expect(status == 400, f"{str(bad)[:40]} gave {status}")
        expect(ai.calls == [], "bad input reached the provider")
        status, text = chat_call(url, key, "BREAK please")
        expect(status == 502 and KEY.encode() not in text and b"secret provider detail" not in text, f"failure: {status} {text[:200]!r}")
        status, text = chat_call(url, key, "BOUNCE please")
        expect(status == 502, f"a redirect from the provider gave {status}")
        expect(all(call["path"] == "/v1/chat/completions" for call in ai.calls), f"paths: {[c['path'] for c in ai.calls]}")
    ai.shutdown()


def check_without_an_ai_the_chat_still_answers_with_the_plain_message():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        url, key = chat_with_ai(w)
        status, raw = chat_call(url, key, "hello")
        expect(status == 200 and "not connected" in json.loads(raw)["reply"], f"chat: {status} {raw[:200]!r}")
        expect(root_post(w, "/v1/brain/capability", key)[0] == 503, "the Root issued a capability with no AI set up")


CHECKS = [check_the_chat_answers_through_the_roots_proxy_and_the_use_is_counted,
          check_a_chat_on_the_linux_agent_uses_the_proxy_too,
          check_the_provider_key_is_nowhere_on_the_agent_the_chat_or_the_roots_files_except_its_env_file,
          check_a_wrong_or_expired_capability_is_refused_with_no_provider_call,
          check_bad_input_never_reaches_the_provider_and_a_provider_failure_is_a_clean_error,
          check_without_an_ai_the_chat_still_answers_with_the_plain_message]
