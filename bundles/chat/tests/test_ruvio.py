"""The Ruvio chat screen's backend: sessions, the conversation routes, runs, persistence, and that every answer has the structure the real Ruvio chat gives."""
import http.client
import json
import pathlib
import sys
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE / "service"))
import brain as brain_client  # noqa: E402
import chat  # noqa: E402
from ruvio import runner  # noqa: E402

KEY = "k" * 43
SHAPES = json.loads((HERE / "tests" / "fixtures" / "maas-shapes.json").read_text())
OPTIONAL_KEYS = {"lastError", "error", "limits", "environment"}


class FakeBrain:
    """Answers like the Root's proxy; steers with attributes. `prompts` records what it was asked."""

    def __init__(self):
        self.prompts, self.failure, self.delay, self.hang = [], None, 0.0, None

    def reply(self, message):
        self.prompts.append(message)
        time.sleep(self.delay)
        if self.hang:
            self.hang.wait(10)
        if self.failure:
            raise self.failure
        return "AI says hello"


def shape(value):
    if isinstance(value, dict):
        return {key: shape(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [shape(value[0])] if value else []
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    return "number" if isinstance(value, (int, float)) else "str"


def same_structure(ours, theirs, path="$"):
    """Problems (as text) where our answer differs in structure from the recorded real one. null and empty lists match anything."""
    if ours == "null" or theirs == "null":
        return []
    if isinstance(ours, dict) and isinstance(theirs, dict):
        problems = [f"{path}: keys differ {sorted(set(ours) ^ set(theirs) - OPTIONAL_KEYS)}"] if (set(ours) - OPTIONAL_KEYS) != (set(theirs) - OPTIONAL_KEYS) else []
        for key in set(ours) & set(theirs):
            problems += same_structure(ours[key], theirs[key], f"{path}.{key}")
        return problems
    if isinstance(ours, list) and isinstance(theirs, list):
        return same_structure(ours[0], theirs[0], path + "[]") if ours and theirs else []
    return [] if ours == theirs else [f"{path}: {ours} instead of {theirs}"]


class Chat:
    """A running chat service on a temporary folder, with a fake brain."""

    def __init__(self, data_dir=None, brain=None):
        self.directory = tempfile.TemporaryDirectory()
        self.data_dir = data_dir or self.directory.name
        self.brain = brain or FakeBrain()
        self.start()

    def start(self):
        app = chat.make_app(self.data_dir, "9.9.9", "testhost", self.brain)
        self.app = app
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), chat.make_handler(KEY, str(HERE / "web"), "9.9.9", "testhost", self.brain, app))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    def close(self):
        self.stop()
        self.directory.cleanup()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=10)
        data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        connection.request(method, path, body=data, headers=headers or {})
        reply = connection.getresponse()
        raw = reply.read()
        connection.close()
        return reply.status, dict(reply.getheaders()), raw


class Person:
    """Someone who opened the chat with the key: holds the session cookie and CSRF token like the screen does."""

    def __init__(self, service):
        self.service = service
        status, headers, _ = service.request("POST", "/auth/open", headers={"Authorization": f"Bearer {KEY}"})
        assert status == 200, status
        self.cookie = headers["Set-Cookie"].split(";")[0]
        self.csrf = self.call("GET", "/api/me", csrf=False)[1]["csrf"]

    def call(self, method, path, body=None, csrf=True, origin=None):
        headers = {"Cookie": self.cookie, "Content-Type": "application/json"}
        if csrf:
            headers["X-CSRF-Token"] = self.csrf
        if origin:
            headers["Origin"] = origin
        status, _, raw = self.service.request(method, path, body, headers)
        return status, json.loads(raw)

    def bot(self):
        return self.call("GET", "/api/agents")[1]["agents"][0]["id"]

    def wait_for_run(self, bot, seconds=5):
        deadline = time.time() + seconds
        while time.time() < deadline:
            runs = self.call("GET", f"/api/agents/{bot}/runs")[1]["runs"]
            if runs and runs[0]["state"] in ("succeeded", "failed", "cancelled", "interrupted"):
                return runs[0]
            time.sleep(0.05)
        raise AssertionError("the run never finished")


class SessionTest(unittest.TestCase):
    def setUp(self):
        self.service = Chat()

    def tearDown(self):
        self.service.close()

    def test_the_right_key_opens_a_session_the_wrong_one_does_not(self):
        for key in (None, "", "wrong", KEY + "x", KEY[:-1]):
            sent = {} if key is None else {"Authorization": f"Bearer {key}"}
            status, headers, raw = self.service.request("POST", "/auth/open", headers=sent)
            self.assertEqual(status, 401, key)
            self.assertNotIn("Set-Cookie", headers)
        status, headers, _ = self.service.request("POST", "/auth/open", headers={"Authorization": f"Bearer {KEY}"})
        self.assertEqual(status, 200)
        cookie = headers["Set-Cookie"]
        self.assertTrue(all(word in cookie for word in ("HttpOnly", "SameSite=Strict", "Path=/")), cookie)
        self.assertNotIn(KEY, cookie)

    def test_the_address_shows_the_chat_screen_only_with_a_session(self):
        person = Person(self.service)
        _, _, without = self.service.request("GET", "/")
        _, _, with_session = self.service.request("GET", "/", headers={"Cookie": person.cookie})
        self.assertIn(b'id="message"', without)
        self.assertIn(b'<div id="app">', with_session)

    def test_the_conversation_routes_need_a_session_and_mutations_need_the_csrf_token(self):
        self.assertEqual(self.service.request("GET", "/api/agents")[0], 401)
        self.assertEqual(self.service.request("GET", "/api/config")[0], 200)
        person = Person(self.service)
        bot = person.bot()
        body = {"text": "hi"}
        self.assertEqual(person.call("POST", f"/api/agents/{bot}/messages", body, csrf=False)[0], 403)
        self.assertEqual(person.call("POST", f"/api/agents/{bot}/messages", body, origin="http://evil.example")[0], 403)
        self.assertEqual(person.call("POST", f"/api/agents/{bot}/messages", body, origin=f"http://127.0.0.1:{self.service.server.server_address[1]}")[0], 202)

    def test_signing_out_ends_the_session(self):
        person = Person(self.service)
        self.assertEqual(self.service.request("POST", "/auth/logout", headers={"Cookie": person.cookie})[0], 200)
        self.assertEqual(person.call("GET", "/api/agents")[0], 401)

    def test_unknown_routes_are_plain_404s_that_leak_nothing(self):
        person = Person(self.service)
        for method, path in (("GET", "/api/nope"), ("GET", "/api/agents/not-an-id/messages"), ("POST", "/api/agents"), ("GET", "/api/agents/" + "0" * 8 + "-0000-0000-0000-" + "0" * 12 + "/messages")):
            status, body = person.call(method, path, {} if method == "POST" else None)
            self.assertEqual(status, 404, path)
            self.assertNotIn("Traceback", json.dumps(body))
        self.assertEqual(self.service.request("POST", "/api/agents/x", b"{}", {"Cookie": person.cookie, "X-CSRF-Token": person.csrf})[0], 404)


class ConversationTest(unittest.TestCase):
    def setUp(self):
        self.service = Chat()
        self.person = Person(self.service)
        self.bot = self.person.bot()

    def tearDown(self):
        self.service.close()

    def send(self, text):
        return self.person.call("POST", f"/api/agents/{self.bot}/messages", {"text": text})

    def test_a_new_machine_has_one_bot_that_greets_you(self):
        agents = self.person.call("GET", "/api/agents")[1]["agents"]
        self.assertEqual([agent["name"] for agent in agents], ["Ruvio"])
        messages = self.person.call("GET", f"/api/agents/{self.bot}/messages")[1]["messages"]
        self.assertEqual([m["role"] for m in messages], ["assistant"])
        self.assertIn("running on testhost", messages[0]["text"])

    def test_a_message_is_answered_through_a_run_with_the_ai_reply_saved(self):
        status, sent = self.send("hello there")
        self.assertEqual(status, 202)
        self.assertEqual((sent["pending"], sent["run"]["state"], sent["messages"][-1]["text"]), (True, "queued", "hello there"))
        run = self.person.wait_for_run(self.bot)
        self.assertEqual(run["state"], "succeeded")
        history = self.person.call("GET", f"/api/agents/{self.bot}/messages")[1]
        self.assertEqual([m["role"] for m in history["messages"]], ["assistant", "user", "assistant"])
        self.assertEqual((history["messages"][-1]["text"], history["pending"]), ("AI says hello", False))
        states = [e["payload"]["state"] for e in self.person.call("GET", f"/api/runs/{run['id']}/events?after=0")[1]["events"] if e["kind"] == "state"]
        self.assertEqual(states, ["queued", "running", "succeeded"])
        self.assertEqual(self.person.call("GET", "/api/usage")[1]["turns"], 1)

    def test_events_can_be_read_from_a_cursor(self):
        self.send("hi")
        run = self.person.wait_for_run(self.bot)
        later = self.person.call("GET", f"/api/runs/{run['id']}/events?after=2")[1]
        self.assertTrue(all(e["sequence"] > 2 for e in later["events"]))
        self.assertEqual(later["run"]["state"], "succeeded")
        self.assertEqual(self.person.call("GET", f"/api/runs/{run['id']}/approvals")[1], {"approvals": []})

    def test_the_ai_is_given_the_conversation_so_far(self):
        self.send("my name is Ada")
        self.person.wait_for_run(self.bot)
        self.send("what is my name?")
        self.person.wait_for_run(self.bot)
        last = self.service.brain.prompts[-1]
        self.assertIn("You: my name is Ada", last)
        self.assertIn("Ruvio: AI says hello", last)
        self.assertTrue(last.endswith("You: what is my name?\nRuvio:"))

    def test_a_second_message_while_the_bot_is_answering_is_refused(self):
        self.service.brain.delay = 0.6
        self.assertEqual(self.send("one")[0], 202)
        status, body = self.send("two")
        self.assertEqual(status, 409)
        self.assertIn("still answering", body["error"])
        self.person.wait_for_run(self.bot)

    def test_bad_messages_are_refused(self):
        for text in ("", "   ", "x" * 4001, 5, None):
            self.assertEqual(self.send(text)[0], 400, repr(text)[:20])
        self.assertEqual(self.person.call("POST", f"/api/agents/{self.bot}/messages", {"nothing": 1})[0], 400)
        self.assertEqual(self.service.request("POST", f"/api/agents/{self.bot}/messages", b"{not json", {"Cookie": self.person.cookie, "X-CSRF-Token": self.person.csrf})[0], 400)

    def test_when_the_ai_fails_the_run_fails_and_the_bot_says_why(self):
        self.service.brain.failure = brain_client.BrainUnavailable("the Root cannot be reached")
        self.send("hi")
        run = self.person.wait_for_run(self.bot)
        self.assertEqual((run["state"], run["error"]), ("failed", "the Root cannot be reached"))
        history = self.person.call("GET", f"/api/agents/{self.bot}/messages")[1]
        self.assertEqual((history["messages"][-1]["role"], history["lastError"]), ("system", "the Root cannot be reached"))
        agent = self.person.call("GET", "/api/agents")[1]["agents"][0]
        self.assertEqual((agent["status"], agent["activity"]["state"]), ("idle", "failed"))

    def test_a_machine_without_an_ai_answers_with_the_plain_message(self):
        self.service.brain.failure = brain_client.BrainNotConfigured()
        self.send("repeat me")
        self.person.wait_for_run(self.bot)
        text = self.person.call("GET", f"/api/agents/{self.bot}/messages")[1]["messages"][-1]["text"]
        self.assertIn("not connected yet", text)
        self.assertTrue(text.endswith("repeat me"), text)

    def test_an_answer_in_progress_can_be_cancelled(self):
        self.service.brain.delay = 0.5
        run = self.send("slow")[1]["run"]
        status, body = self.person.call("POST", f"/api/runs/{run['id']}/cancel")
        self.assertEqual((status, body["run"]["state"]), (200, "cancelled"))
        time.sleep(0.8)
        roles = [m["role"] for m in self.person.call("GET", f"/api/agents/{self.bot}/messages")[1]["messages"]]
        self.assertEqual(roles, ["assistant", "user"], "a cancelled answer must not appear afterwards")

    def test_unread_answers_are_counted_until_the_bot_is_opened(self):
        self.assertEqual(self.person.call("GET", "/api/agents")[1]["agents"][0]["unreadCount"], 1)
        self.person.call("POST", f"/api/agents/{self.bot}/read", {})
        self.assertEqual(self.person.call("GET", "/api/agents")[1]["agents"][0]["unreadCount"], 0)
        self.send("hi")
        self.person.wait_for_run(self.bot)
        self.assertEqual(self.person.call("GET", "/api/agents")[1]["agents"][0]["unreadCount"], 2)

    def test_bots_can_be_added_renamed_and_deleted_up_to_the_limit(self):
        status, made = self.person.call("POST", "/api/new-bot", {"avatarShape": "blob", "avatarColor": "#2563eb", "ideas": []})
        self.assertEqual((status, made["agent"]["name"], made["agent"]["avatarShape"]), (202, "New bot", "blob"))
        self.assertEqual(made["messages"][0]["role"], "assistant")
        new_id = made["agent"]["id"]
        status, renamed = self.person.call("PATCH", f"/api/agents/{new_id}", {"name": "Helper", "title": "Researcher", "summary": "Finds things", "description": "Be brief."})
        self.assertEqual((status, renamed["agent"]["name"], renamed["agent"]["title"]), (200, "Helper", "Researcher"))
        self.assertEqual(self.person.call("PATCH", f"/api/agents/{new_id}", {"name": "   "})[1]["agent"]["name"], "Helper", "a blank name changes nothing")
        self.assertEqual(self.person.call("DELETE", f"/api/agents/{new_id}")[0], 200)
        self.assertEqual(len(self.person.call("GET", "/api/agents")[1]["agents"]), 1)
        for _ in range(7):
            self.person.call("POST", "/api/new-bot", {})
        self.assertEqual(self.person.call("POST", "/api/new-bot", {})[0], 403)

    def test_each_bot_keeps_its_own_conversation(self):
        other = self.person.call("POST", "/api/new-bot", {})[1]["agent"]["id"]
        self.send("only for the first bot")
        self.person.wait_for_run(self.bot)
        texts = [m["text"] for m in self.person.call("GET", f"/api/agents/{other}/messages")[1]["messages"]]
        self.assertFalse(any("only for the first bot" in text for text in texts))


class PersistenceTest(unittest.TestCase):
    def test_conversations_survive_a_restart_and_work_in_progress_is_marked_interrupted(self):
        service = Chat()
        try:
            person = Person(service)
            bot = person.bot()
            person.call("POST", f"/api/agents/{bot}/messages", {"text": "remember me"})
            person.wait_for_run(bot)
            service.brain.hang = threading.Event()
            person.call("POST", f"/api/agents/{bot}/messages", {"text": "unfinished"})
            old_brain, old_store = service.brain, service.app.store
            service.stop()
            service.brain = FakeBrain()
            service.start()
            person = Person(service)
            messages = person.call("GET", f"/api/agents/{bot}/messages")[1]
            self.assertEqual([m["text"] for m in messages["messages"] if m["role"] == "user"], ["remember me", "unfinished"])
            self.assertEqual(messages["messages"][-1]["role"], "system")
            self.assertIn("restarted", messages["messages"][-1]["text"])
            self.assertFalse(messages["pending"])
            self.assertEqual(person.call("GET", f"/api/agents/{bot}/runs")[1]["runs"][0]["state"], "interrupted")
            self.assertEqual(len(person.call("GET", "/api/agents")[1]["agents"]), 1, "a restart must not make a second bot")
            old_brain.hang.set()
            deadline = time.time() + 5
            while time.time() < deadline and old_store.active_run(bot) is not None:
                time.sleep(0.05)
            time.sleep(0.1)
        finally:
            service.close()


class SameStructureAsTheRealRuvioChatTest(unittest.TestCase):
    """Each answer must have the keys and kinds of value the real Ruvio chat gives (recorded in fixtures/maas-shapes.json), or the screen misbehaves."""

    def setUp(self):
        self.service = Chat()
        self.person = Person(self.service)
        self.bot = self.person.bot()

    def tearDown(self):
        self.service.close()

    def check(self, name, ours):
        self.assertEqual(same_structure(shape(ours), SHAPES[name]), [], name)

    def test_every_route_the_screen_loads_at_start(self):
        self.check("config", self.person.call("GET", "/api/config")[1])
        for name, path in (("me", "/api/me"), ("agents", "/api/agents"), ("usage", "/api/usage"), ("files", "/api/files"), ("storage_gate", "/api/storage/gate"),
                           ("storage", "/api/storage"), ("apps", "/api/apps"), ("connectors", "/api/connectors"), ("environment", "/api/environment"),
                           ("routines", "/api/routines"), ("memory", f"/api/agents/{self.bot}/memory"), ("runs_empty", f"/api/agents/{self.bot}/runs")):
            self.check(name, self.person.call("GET", path)[1])

    def test_sending_a_message_and_following_the_run(self):
        sent = self.person.call("POST", f"/api/agents/{self.bot}/messages", {"text": "hello"})[1]
        self.check("send", sent)
        run = self.person.wait_for_run(self.bot)
        self.check("events", self.person.call("GET", f"/api/runs/{run['id']}/events?after=0")[1])
        self.check("approvals", self.person.call("GET", f"/api/runs/{run['id']}/approvals")[1])
        self.check("runs", self.person.call("GET", f"/api/agents/{self.bot}/runs")[1])
        self.check("messages", self.person.call("GET", f"/api/agents/{self.bot}/messages")[1])
        self.check("read", self.person.call("POST", f"/api/agents/{self.bot}/read", {})[1])

    def test_a_failed_answer_and_a_new_bot(self):
        self.service.brain.failure = brain_client.BrainUnavailable("the AI could not answer right now")
        self.person.call("POST", f"/api/agents/{self.bot}/messages", {"text": "hello"})
        self.person.wait_for_run(self.bot)
        self.check("agents_after_failure", self.person.call("GET", "/api/agents")[1])
        self.check("new_bot", self.person.call("POST", "/api/new-bot", {"avatarShape": "blob", "avatarColor": "#2563eb", "ideas": []})[1])


class PromptTest(unittest.TestCase):
    def rows(self, count):
        return [{"role": "user" if n % 2 == 0 else "assistant", "text": f"line {n}"} for n in range(count)]

    def test_the_prompt_names_the_bot_and_the_machine_and_ends_with_the_new_message(self):
        prompt = runner.build_prompt("Ruvio", "mac-1", self.rows(2), "next")
        self.assertIn("You are Ruvio", prompt)
        self.assertIn("mac-1", prompt)
        self.assertTrue(prompt.endswith("You: next\nRuvio:"))

    def test_only_the_recent_turns_are_kept_and_the_prompt_always_fits(self):
        prompt = runner.build_prompt("Ruvio", "mac-1", self.rows(40), "next")
        self.assertNotIn("line 0\n", prompt)
        self.assertIn("line 39", prompt)
        big = [{"role": "user", "text": "x" * 1000} for _ in range(12)]
        self.assertLessEqual(len(runner.build_prompt("Ruvio", "mac-1", big, "y" * 500)), runner.MAX_PROMPT_CHARS)

    def test_a_system_message_is_not_part_of_the_conversation(self):
        prompt = runner.build_prompt("Ruvio", "mac-1", [{"role": "system", "text": "I could not answer"}], "hi")
        self.assertNotIn("could not answer", prompt)


class StaticFilesTest(unittest.TestCase):
    def setUp(self):
        self.service = Chat()

    def tearDown(self):
        self.service.close()

    def test_the_screen_files_are_served_with_the_right_types_and_a_strict_policy(self):
        for path, kind in (("/open.js", "text/javascript"), ("/open.css", "text/css"), ("/ruvio-mark.svg", "image/svg+xml"), ("/theme-init.js", "text/javascript"), ("/boot.css", "text/css")):
            status, headers, raw = self.service.request("GET", path)
            self.assertEqual(status, 200, path)
            self.assertTrue(headers["Content-Type"].startswith(kind), path)
            self.assertTrue(raw)
            self.assertNotIn("unsafe", headers["Content-Security-Policy"])
            self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        asset = next((HERE / "web" / "assets").glob("*.js")).name
        status, headers, _ = self.service.request("GET", f"/assets/{asset}")
        self.assertEqual((status, "immutable" in headers["Cache-Control"]), (200, True))

    def test_nothing_outside_the_web_folder_or_hidden_is_served(self):
        for path in ("/../service/chat.py", "/%2e%2e/service/chat.py", "/assets/../../service/chat.py", "/.hidden", "/assets/", "/assets", "/index.html", "/VERSION", "//etc/passwd", "/a\\b"):
            self.assertEqual(self.service.request("GET", path)[0], 404, path)


if __name__ == "__main__":
    unittest.main()
