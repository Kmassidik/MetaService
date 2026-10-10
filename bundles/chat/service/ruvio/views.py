"""The JSON the Ruvio chat screen expects, built from what the store holds. Pure functions: no files, no network, easy to test."""

LIMITS = {"cpu": 2, "maxAgents": 8, "maxTeams": 3, "memoryMB": 3072, "workspaceBytes": 10_000_000_000}
HOST_STATE = {"reason": None, "registrationsOpen": False, "writesAllowed": True}
COMPUTER_READY = {"state": "ready", "message": "This bot runs on this machine."}
MODEL = "auto"
PREVIEW_CHARS = 140
RUN_ACTIVITY = {"queued": "running", "running": "running"}


def config():
    return {"capacity": HOST_STATE, "googleConfigured": False}


def me(owner, csrf, completed_at):
    return {
        "csrf": csrf, "limits": LIMITS,
        "onboarding": {"completedAt": completed_at, "goal": "machine", "goalDetail": "", "source": "panel", "sourceDetail": ""},
        "user": {"access": "active", "email": owner["email"], "id": owner["id"], "name": owner["name"]},
    }


def message(row, with_attachments=True):
    shown = {"attachmentIds": [], "createdAt": row["created_at"], "id": row["id"], "role": row["role"], "text": row["text"]}
    if with_attachments:
        shown["attachments"] = []
    return shown


def run(row):
    shown = {
        "agentId": row["agent_id"], "attachmentIds": [], "createdAt": row["created_at"], "firstEventSequence": row["first_seq"] or 1,
        "id": row["id"], "lastEventSequence": row["last_seq"] or 1, "model": MODEL, "state": row["state"], "updatedAt": row["updated_at"],
    }
    if row["error"]:
        shown["error"] = row["error"]
    return shown


def preview(messages):
    for row in reversed(messages):
        text = " ".join(row["text"].split())
        if text:
            return text[:PREVIEW_CHARS]
    return ""


def activity(last_run):
    if last_run is None:
        return {"state": "idle", "tool": None}
    state = RUN_ACTIVITY.get(last_run["state"], last_run["state"] if last_run["state"] == "failed" else "idle")
    if state == "idle":
        return {"state": "idle", "tool": None}
    return {"model": MODEL, "startedAt": last_run["created_at"], "state": state, "title": last_run["title"], "tool": None}


def agent(row, messages, last_run, unread, with_activity=True):
    """A bot as the list shows it. Right after one is made or opened the real chat leaves `activity` out, so `with_activity` can drop it."""
    working = last_run is not None and last_run["state"] in RUN_ACTIVITY
    shown = {
        "avatarColor": row["avatar_color"], "avatarShape": row["avatar_shape"], "createdAt": row["created_at"],
        "description": row["description"], "hidden": False, "id": row["id"], "kind": "bot", "lastMessagePreview": preview(messages),
        "lastReadSequence": 0, "leadAgentId": None, "memberAgentIds": [], "model": MODEL, "name": row["name"], "notifyFinished": True,
        "notifyNeedsInput": True, "pinned": bool(row["pinned"]), "queuedMessage": False, "status": "running" if working else "idle",
        "summary": row["summary"], "title": row["title"], "unreadCount": unread,
    }
    if with_activity:
        shown["activity"] = activity(last_run)
    if last_run is not None and last_run["state"] == "failed":
        shown["lastError"] = last_run["error"] or "The answer did not finish."
    return shown


def usage(turns):
    return {"blocked": False, "lifetime": {"tokens": 0, "turns": turns}, "monthly": {"tokens": 0, "turns": turns}, "remaining": 1_000_000, "tokens": 0, "turns": turns}


def storage_gate(can_create):
    return {"canCreateAgent": can_create, "host": HOST_STATE, "limits": LIMITS}


def storage(can_create):
    return {**storage_gate(can_create), "computer": {"state": "not_created", "system": None, "workspace": None},
            "results": {"availableBytes": 2_147_483_648, "limitBytes": 2_147_483_648, "state": "ok", "usedBytes": 0}}


def history(messages, pending, last_error):
    shown = {"computer": COMPUTER_READY, "messages": [message(row) for row in messages], "pending": pending}
    if last_error:
        shown["lastError"] = last_error
    return shown
