"""The conversations on this machine, in one SQLite file next to the access key: bots, messages, runs and their events."""
import json
import sqlite3
import threading
import uuid

SCHEMA = """
CREATE TABLE IF NOT EXISTS agents (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '', summary TEXT NOT NULL DEFAULT '',
  avatar_shape TEXT NOT NULL, avatar_color TEXT NOT NULL, created_at TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, read_count INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS messages (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, agent_id TEXT NOT NULL, role TEXT NOT NULL, text TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS messages_by_agent ON messages (agent_id, seq);
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, state TEXT NOT NULL, error TEXT, title TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS runs_by_agent ON runs (agent_id, created_at);
CREATE TABLE IF NOT EXISTS events (
  run_id TEXT NOT NULL, sequence INTEGER NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (run_id, sequence));
CREATE TABLE IF NOT EXISTS usage (id INTEGER PRIMARY KEY CHECK (id = 1), turns INTEGER NOT NULL);
INSERT OR IGNORE INTO usage (id, turns) VALUES (1, 0);
"""
TERMINAL_STATES = ("succeeded", "failed", "cancelled", "interrupted")


def new_id():
    return str(uuid.uuid4())


class Store:
    def __init__(self, path, clock):
        self.clock = clock
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)

    def _all(self, sql, args=()):
        with self.lock:
            return [dict(row) for row in self.db.execute(sql, args)]

    def _one(self, sql, args=()):
        rows = self._all(sql, args)
        return rows[0] if rows else None

    def _run(self, sql, args=()):
        with self.lock:
            self.db.execute(sql, args)

    # --- bots
    def agents(self):
        return self._all("SELECT * FROM agents ORDER BY created_at, rowid")

    def agent(self, agent_id):
        return self._one("SELECT * FROM agents WHERE id = ?", (agent_id,))

    def create_agent(self, name, description, shape, color):
        agent_id = new_id()
        self._run("INSERT INTO agents (id, name, description, avatar_shape, avatar_color, created_at) VALUES (?, ?, ?, ?, ?, ?)", (agent_id, name, description, shape, color, self.clock()))
        return self.agent(agent_id)

    def update_agent(self, agent_id, fields):
        for column, value in fields.items():
            self._run(f"UPDATE agents SET {column} = ? WHERE id = ?", (value, agent_id))
        return self.agent(agent_id)

    def delete_agent(self, agent_id):
        with self.lock:
            run_ids = [row["id"] for row in self._all("SELECT id FROM runs WHERE agent_id = ?", (agent_id,))]
            for run_id in run_ids:
                self.db.execute("DELETE FROM events WHERE run_id = ?", (run_id,))
            for table in ("runs", "messages"):
                self.db.execute(f"DELETE FROM {table} WHERE agent_id = ?", (agent_id,))
            self.db.execute("DELETE FROM agents WHERE id = ?", (agent_id,))

    def mark_read(self, agent_id):
        self._run("UPDATE agents SET read_count = (SELECT COUNT(*) FROM messages WHERE agent_id = ?) WHERE id = ?", (agent_id, agent_id))

    def unread(self, agent_id):
        row = self._one("SELECT (SELECT COUNT(*) FROM messages WHERE agent_id = a.id) AS total, a.read_count AS seen FROM agents a WHERE a.id = ?", (agent_id,))
        return 0 if row is None else max(0, row["total"] - row["seen"])

    # --- messages
    def messages(self, agent_id):
        return self._all("SELECT id, role, text, created_at FROM messages WHERE agent_id = ? ORDER BY seq", (agent_id,))

    def add_message(self, agent_id, role, text):
        message_id, now = new_id(), self.clock()
        self._run("INSERT INTO messages (id, agent_id, role, text, created_at) VALUES (?, ?, ?, ?, ?)", (message_id, agent_id, role, text, now))
        return {"id": message_id, "role": role, "text": text, "created_at": now}

    # --- runs
    def create_run(self, agent_id, title):
        run_id, now = new_id(), self.clock()
        self._run("INSERT INTO runs (id, agent_id, state, title, created_at, updated_at) VALUES (?, ?, 'queued', ?, ?, ?)", (run_id, agent_id, title, now, now))
        self.add_event(run_id, "state", {"state": "queued"})
        return self.run(run_id)

    def run(self, run_id):
        return self._one("SELECT r.*, (SELECT MIN(sequence) FROM events WHERE run_id = r.id) AS first_seq, (SELECT MAX(sequence) FROM events WHERE run_id = r.id) AS last_seq "
                         "FROM runs r WHERE r.id = ?", (run_id,))

    def runs(self, agent_id):
        return [self.run(row["id"]) for row in self._all("SELECT id FROM runs WHERE agent_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 30", (agent_id,))]

    def active_run(self, agent_id):
        marks = ",".join("?" * len(TERMINAL_STATES))
        row = self._one(f"SELECT id FROM runs WHERE agent_id = ? AND state NOT IN ({marks}) ORDER BY created_at DESC LIMIT 1", (agent_id, *TERMINAL_STATES))
        return None if row is None else self.run(row["id"])

    def set_run_state(self, run_id, state, error=None):
        self._run("UPDATE runs SET state = ?, error = ?, updated_at = ? WHERE id = ?", (state, error, self.clock(), run_id))
        self.add_event(run_id, "state", {"state": state})

    def add_event(self, run_id, kind, payload):
        with self.lock:
            last = self.db.execute("SELECT COALESCE(MAX(sequence), 0) FROM events WHERE run_id = ?", (run_id,)).fetchone()[0]
            self.db.execute("INSERT INTO events (run_id, sequence, kind, payload, created_at) VALUES (?, ?, ?, ?, ?)", (run_id, last + 1, kind, json.dumps(payload), self.clock()))

    def events(self, run_id, after):
        rows = self._all("SELECT sequence, kind, payload, created_at FROM events WHERE run_id = ? AND sequence > ? ORDER BY sequence", (run_id, after))
        return [{"sequence": r["sequence"], "kind": r["kind"], "payload": json.loads(r["payload"]), "createdAt": r["created_at"], "runId": run_id} for r in rows]

    def interrupt_open_runs(self):
        """A run that was working when this chat stopped cannot continue: it is marked interrupted, and its bot says so."""
        marks = ",".join("?" * len(TERMINAL_STATES))
        for row in self._all(f"SELECT id, agent_id FROM runs WHERE state NOT IN ({marks})", TERMINAL_STATES):
            self.set_run_state(row["id"], "interrupted", "This chat was restarted before the answer was ready.")
            self.add_message(row["agent_id"], "system", "This chat was restarted before the answer was ready. Send your message again.")

    # --- usage
    def count_turn(self):
        self._run("UPDATE usage SET turns = turns + 1 WHERE id = 1")

    def turns(self):
        return self._one("SELECT turns FROM usage WHERE id = 1")["turns"]
