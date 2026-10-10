"""Answers a message in the background, like a run in the Ruvio chat: queued, running, then succeeded or failed, with the reply saved as the bot's message."""
import threading

from replies import reply_to

MAX_PROMPT_CHARS = 3800   # the Root's AI proxy takes at most 4000 characters in one message
HISTORY_TURNS = 12
PERSONA = "You are {name}, a helpful AI assistant running on the machine {host}. Answer the last message of this conversation briefly and clearly."
FAILED_TEXT = "I could not answer: {reason}."


def build_prompt(agent_name, host, earlier, text):
    """One message for the AI proxy that carries the recent conversation, newest turns kept when it is too long."""
    lines = [("You" if row["role"] == "user" else agent_name) + ": " + row["text"] for row in earlier if row["role"] in ("user", "assistant")]
    lines = lines[-HISTORY_TURNS:] + ["You: " + text, agent_name + ":"]
    head = PERSONA.format(name=agent_name, host=host) + "\n\nConversation:\n"
    room = MAX_PROMPT_CHARS - len(head)
    kept = []
    for line in reversed(lines):
        if len(line) > room:
            break
        kept.append(line)
        room -= len(line) + 1
    return head + "\n".join(reversed(kept))


class Runner:
    def __init__(self, store, brain, version, host):
        self.store, self.brain, self.version, self.host = store, brain, version, host
        self.cancelled = set()
        self.lock = threading.Lock()

    def start(self, agent, text, earlier):
        """Queues the answer to `text` and returns the run; the work happens on its own thread."""
        run = self.store.create_run(agent["id"], text[:80])
        worker = threading.Thread(target=self._execute, args=(run["id"], agent, text, earlier), daemon=True)
        worker.start()
        return run

    def cancel(self, run_id):
        with self.lock:
            self.cancelled.add(run_id)

    def _is_cancelled(self, run_id):
        with self.lock:
            return run_id in self.cancelled

    def _execute(self, run_id, agent, text, earlier):
        self.store.set_run_state(run_id, "running")
        self.store.add_event(run_id, "step", {"name": "Asking the AI", "phase": "start"})
        prompt = build_prompt(agent["name"], self.host, earlier, text)
        status, reply = reply_to(prompt, self.brain, self.version, self.host, plain_text=text)
        if self._is_cancelled(run_id):
            self.store.set_run_state(run_id, "cancelled")
            return
        self.store.add_event(run_id, "step", {"name": "Asking the AI", "phase": "end"})
        if status != 200:
            self._fail(run_id, agent["id"], reply)
            return
        self.store.add_message(agent["id"], "assistant", reply)
        self.store.count_turn()
        self.store.set_run_state(run_id, "succeeded")

    def _fail(self, run_id, agent_id, reason):
        self.store.add_message(agent_id, "system", FAILED_TEXT.format(reason=reason))
        self.store.set_run_state(run_id, "failed", reason)
