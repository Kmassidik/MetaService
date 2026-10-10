"""The routes the Ruvio chat screen calls. Each handler takes a Call and returns (status, JSON). Anything not listed is a plain 404, so the screen shows an empty panel instead of breaking."""
import re

from ruvio import views
from ruvio.store import TERMINAL_STATES

MAX_TEXT_CHARS = 4000
MAX_NAME_CHARS = 80
MAX_FIELD_CHARS = 2000
WELCOME = "Hi 👋 I'm {name}, running on {host}. What can I help you with?"
NEW_BOT_NAME = "New bot"
NEW_BOT_DESCRIPTION = "A helpful assistant."
DEFAULT_SHAPE, DEFAULT_COLOR = "pebble", "#1a1a1a"
PATCHABLE = {"name": "name", "description": "description", "title": "title", "summary": "summary"}
NOT_FOUND = (404, {"error": "Not found."})
EMPTY_LISTS = {"/api/files": "files", "/api/apps": "apps", "/api/connectors": "connectors", "/api/routines": "routines"}


class Call:
    """One request, as the handlers see it."""

    def __init__(self, method, path, query, body, session, app):
        self.method, self.path, self.query, self.body, self.session, self.app = method, path, query, body, session, app
        self.match = None

    def arg(self, index=1):
        return self.match.group(index)


class App:
    """What the handlers share: the store, the runner and who owns this machine's chat."""

    def __init__(self, store, runner, owner, host, completed_at):
        self.store, self.runner, self.owner, self.host, self.completed_at = store, runner, owner, host, completed_at

    def agent_json(self, row, with_activity=True):
        messages = self.store.messages(row["id"])
        runs = self.store.runs(row["id"])
        return views.agent(row, messages, runs[0] if runs else None, self.store.unread(row["id"]), with_activity)

    def welcome(self, agent):
        text = WELCOME.format(name=agent["name"], host=self.host)
        return self.store.add_message(agent["id"], "assistant", text)


def _error(status, text):
    return status, {"error": text}


def _number(text):
    return int(text) if text.isdigit() else 0


def _text_field(body, name, limit):
    value = body.get(name)
    return value.strip() if isinstance(value, str) and len(value.strip()) <= limit else None


def get_config(call):
    return 200, views.config()


def get_me(call):
    return 200, views.me(call.app.owner, call.session.csrf, call.app.completed_at)


def ok(call):
    return 200, {"ok": True}


def list_agents(call):
    app = call.app
    return 200, {"agents": [app.agent_json(row) for row in app.store.agents()], "limits": views.LIMITS}


def new_bot(call):
    app = call.app
    if len(app.store.agents()) >= views.LIMITS["maxAgents"]:
        return _error(403, "This machine's chat is full of bots. Delete one first.")
    shape = _text_field(call.body, "avatarShape", 40) or DEFAULT_SHAPE
    color = _text_field(call.body, "avatarColor", 20) or DEFAULT_COLOR
    agent = app.store.create_agent(NEW_BOT_NAME, NEW_BOT_DESCRIPTION, shape, color)
    welcome = app.welcome(agent)
    return 202, {"agent": app.agent_json(agent, with_activity=False), "environment": {"stage": "ready", "state": "ready"}, "messages": [views.message(welcome, with_attachments=False)]}


def patch_agent(call):
    app = call.app
    agent = app.store.agent(call.arg())
    if agent is None:
        return NOT_FOUND
    changes = {}
    for field, column in PATCHABLE.items():
        value = _text_field(call.body, field, MAX_NAME_CHARS if field == "name" else MAX_FIELD_CHARS)
        if value is not None and (value or field != "name"):
            changes[column] = value
    return 200, {"agent": app.agent_json(app.store.update_agent(agent["id"], changes))}


def delete_agent(call):
    if call.app.store.agent(call.arg()) is None:
        return NOT_FOUND
    call.app.store.delete_agent(call.arg())
    return 200, {"ok": True}


def get_messages(call):
    store = call.app.store
    if store.agent(call.arg()) is None:
        return NOT_FOUND
    runs = store.runs(call.arg())
    failed = runs[0] if runs and runs[0]["state"] == "failed" else None
    return 200, views.history(store.messages(call.arg()), store.active_run(call.arg()) is not None, failed["error"] if failed else None)


def send_message(call):
    app, store = call.app, call.app.store
    agent = store.agent(call.arg())
    if agent is None:
        return NOT_FOUND
    text = _text_field(call.body, "text", MAX_TEXT_CHARS)
    if not text:
        return _error(400, f"Write a message of up to {MAX_TEXT_CHARS} characters.")
    if store.active_run(agent["id"]) is not None:
        return _error(409, "This bot is still answering. Wait for it to finish.")
    earlier = store.messages(agent["id"])
    saved = store.add_message(agent["id"], "user", text)
    run = app.runner.start(agent, text, earlier)
    shown = views.history(earlier + [{**saved, "created_at": saved["created_at"]}], True, None)
    return 202, {**shown, "computer": {"message": "A run is active.", "state": "busy"}, "run": views.run(run)}


def mark_read(call):
    app = call.app
    if app.store.agent(call.arg()) is None:
        return NOT_FOUND
    app.store.mark_read(call.arg())
    return 200, {"agent": app.agent_json(app.store.agent(call.arg()), with_activity=False)}


def list_runs(call):
    if call.app.store.agent(call.arg()) is None:
        return NOT_FOUND
    return 200, {"runs": [views.run(row) for row in call.app.store.runs(call.arg())]}


def get_events(call):
    store = call.app.store
    row = store.run(call.arg())
    if row is None:
        return NOT_FOUND
    after = _number(call.query.get("after", ["0"])[0])
    events = store.events(row["id"], after)
    return 200, {"cursor": events[-1]["sequence"] if events else after, "events": events, "run": views.run(row)}


def get_approvals(call):
    return (200, {"approvals": []}) if call.app.store.run(call.arg()) else NOT_FOUND


def cancel_run(call):
    store = call.app.store
    row = store.run(call.arg())
    if row is None:
        return NOT_FOUND
    if row["state"] in TERMINAL_STATES:
        return 200, {"run": views.run(row)}
    call.app.runner.cancel(row["id"])
    store.set_run_state(row["id"], "cancelled")
    return 200, {"run": views.run(store.run(row["id"]))}


def get_usage(call):
    return 200, views.usage(call.app.store.turns())


def get_storage_gate(call):
    return 200, views.storage_gate(len(call.app.store.agents()) < views.LIMITS["maxAgents"])


def get_storage(call):
    return 200, views.storage(len(call.app.store.agents()) < views.LIMITS["maxAgents"])


def get_environment(call):
    return 200, {"environment": None}


def get_memory(call):
    return (200, {"entries": []}) if call.app.store.agent(call.arg()) else NOT_FOUND


def empty_list(call):
    return 200, {EMPTY_LISTS[call.path]: []}


ID = r"([0-9a-f-]{36})"
ROUTES = [
    ("GET", r"/api/config", get_config, False),
    ("GET", r"/api/me", get_me, True),
    ("POST", r"/api/onboarding", ok, True),
    ("GET", r"/api/agents", list_agents, True),
    ("POST", r"/api/new-bot", new_bot, True),
    ("PATCH", rf"/api/agents/{ID}", patch_agent, True),
    ("DELETE", rf"/api/agents/{ID}", delete_agent, True),
    ("GET", rf"/api/agents/{ID}/messages", get_messages, True),
    ("POST", rf"/api/agents/{ID}/messages", send_message, True),
    ("POST", rf"/api/agents/{ID}/read", mark_read, True),
    ("GET", rf"/api/agents/{ID}/runs", list_runs, True),
    ("GET", rf"/api/agents/{ID}/memory", get_memory, True),
    ("GET", rf"/api/runs/{ID}/events", get_events, True),
    ("GET", rf"/api/runs/{ID}/approvals", get_approvals, True),
    ("POST", rf"/api/runs/{ID}/cancel", cancel_run, True),
    ("GET", r"/api/usage", get_usage, True),
    ("GET", r"/api/storage/gate", get_storage_gate, True),
    ("GET", r"/api/storage", get_storage, True),
    ("GET", r"/api/environment", get_environment, True),
] + [("GET", re.escape(path), empty_list, True) for path in EMPTY_LISTS]
COMPILED = [(method, re.compile(pattern + "$"), handler, needs_session) for method, pattern, handler, needs_session in ROUTES]
MUTATING = ("POST", "PATCH", "DELETE", "PUT")


def route(method, path):
    """(handler, match, needs_session) for a request, or None."""
    for wanted, pattern, handler, needs_session in COMPILED:
        match = pattern.match(path) if wanted == method else None
        if match:
            return handler, match, needs_session
    return None
