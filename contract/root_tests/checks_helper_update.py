"""Update helper: what the parent knows about each machine's helper build (agent_build, update), and POST /api/machines/{id}/update-helper. A real Root, a real OpenSSH server on
loopback and the real macOS helper behind a small wrapper, so the real update script runs against a throwaway box folder: new program in place, old one kept, rollback when the new
one does not start, the helper's state folder untouched."""
import copy
import hashlib
import json
import pathlib
import sqlite3
import tempfile
import time

from contract.agent_tests.support import MACOS_BINARY
from contract.root_tests.checks_remote import authorize_parent, remote
from contract.root_tests.checks_remote_install import add_body, box_folder, running as pid_alive, start_install, wait_for_job
from contract.root_tests.support import Browser, enrolled_machine, expect, good_heartbeat

UPDATE_PATH = "/api/machines/{}/update-helper"
OLD_TEXT = f'#!/bin/sh\n# build A\nexec {MACOS_BINARY} "$@"\n'
NEW_TEXT = f'#!/bin/sh\n# build B, a different program with a longer text\nexec {MACOS_BINARY} "$@"\n'
BROKEN_TEXT = "#!/bin/sh\n# a build that stops at once\nexit 1\n"
SETTLE_SECONDS = 8
UPDATE_REQUEST_SECONDS = 90  # the script waits for the new program twice when it has to roll back


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def wrapper(text):
    path = pathlib.Path(tempfile.mkdtemp(prefix="ms-wrapper-")) / "metaservice-agent"
    write_wrapper(path, text)
    return path


def write_wrapper(path, text):
    path.write_text(text)
    path.chmod(0o755)


def heartbeat(root, token, **facts):
    body = copy.deepcopy(good_heartbeat())
    body["facts"].update({"os": "macos", "arch": "arm64"})
    body["facts"].update(facts)
    reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)
    expect(reply.status == 204, f"heartbeat gave {reply.status}: {reply.raw[:150]!r}")


def machine(operator, name):
    reply = operator.request("GET", f"/api/machines/{name}")
    expect(reply.status == 200, f"machine {name}: {reply.status}")
    return reply.body


def listed(operator, name):
    return next(item for item in operator.request("GET", "/api/machines").body["machines"] if item["name"] == name)


def install(operator, server, box):
    authorize_parent(operator, server)
    job = wait_for_job(operator, start_install(operator, add_body(server, box)).body["id"])
    expect(job["state"] == "done", f"install: {job.get('error')}")


def audit_results(operator):
    entries = operator.request("GET", "/api/audit?limit=100").body["entries"]
    return [json.loads(entry["detail"]).get("result") for entry in entries if entry["action"] == "helper.update"]


def check_the_update_route_is_guarded_and_knows_which_machines_exist():
    with remote() as (root, operator, server):
        enrolled_machine(operator, "mini")
        path = UPDATE_PATH.format("mini")
        expect(Browser(root, auto_login=False).request("POST", path, {}).status == 401, "no login")
        expect(operator.request("POST", path, {}).status == 403, "no CSRF token")
        expect(operator.write("POST", path, {}, origin="http://evil.example").status == 403, "wrong origin")
        expect(operator.write("POST", UPDATE_PATH.format("nobody"), {}).status == 404, "unknown machine")
        expect(operator.write("POST", UPDATE_PATH.format("a;b"), {}).status == 404, "a bad id")
        expect(operator.write("GET", path).status in (404, 405), "only POST")


def check_a_machine_reports_its_build_and_the_parent_says_whether_a_different_one_is_on_offer():
    with remote() as (root, operator, server):
        token = enrolled_machine(operator, "mini")
        own = hashlib.sha256(pathlib.Path(MACOS_BINARY).read_bytes()).hexdigest()
        heartbeat(root, token)
        old = machine(operator, "mini")
        expect(old["agent_build"] is None, f"an old helper says no build: {old['agent_build']!r}")
        expect(old["update"] == {"available": True, "current_build": None, "newest_build": own, "reason": None}, f"old helper: {old['update']}")
        heartbeat(root, token, agent_build="ab" * 32)
        other = machine(operator, "mini")
        expect(other["agent_build"] == "ab" * 32 and other["update"]["available"] is True and other["update"]["current_build"] == "ab" * 32, f"a different build: {other['update']}")
        expect(listed(operator, "mini")["update"] == other["update"] and listed(operator, "mini")["agent_build"] == "ab" * 32, "the list carries the same")
        heartbeat(root, token, agent_build=own)
        same = machine(operator, "mini")
        expect(same["update"]["available"] is False and same["update"]["newest_build"] == own and same["update"]["reason"] is None, f"the newest build: {same['update']}")
        heartbeat(root, token)
        expect(machine(operator, "mini")["agent_build"] is None, "a heartbeat that stops saying it clears it")
        heartbeat(root, token, os="linux", arch="aarch64", agent_build="ab" * 32)
        linux = machine(operator, "mini")["update"]
        expect(linux["available"] is False and linux["newest_build"] is None and linux["reason"], f"no program for linux-arm64: {linux}")


def check_a_hostile_build_is_refused_at_the_heartbeat():
    with remote() as (root, operator, server):
        token = enrolled_machine(operator, "mini")
        for bad in ["<script>alert(1)</script>", "AB" * 32, "ab" * 31, "ab" * 33, "$(reboot)", 5, ["a"], ""]:
            body = copy.deepcopy(good_heartbeat())
            body["facts"]["agent_build"] = bad
            reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)
            expect(reply.status == 400, f"{bad!r} gave {reply.status}")


def check_refusals_are_plain_409s_and_the_route_is_limited_per_machine():
    with remote() as (root, operator, server):
        token = enrolled_machine(operator, "mini")
        heartbeat(root, token, os="linux", arch="aarch64")
        no_build = operator.write("POST", UPDATE_PATH.format("mini"), {})
        expect(no_build.status == 409 and no_build.body["error"]["code"] == "no_build", f"no build: {no_build.status} {no_build.raw[:200]!r}")
        heartbeat(root, token)
        not_installed = operator.write("POST", UPDATE_PATH.format("mini"), {})
        expect(not_installed.status == 409 and not_installed.body["error"]["code"] == "login_needed", f"not added over SSH: {not_installed.status}")
        expect("add it again" in not_installed.body["error"]["message"], not_installed.body["error"]["message"])
        third = operator.write("POST", UPDATE_PATH.format("mini"), {})
        expect(third.status == 429, f"the third in a minute: {third.status}")
        expect(audit_results(operator)[:2] == ["login_needed", "no_build"] or "rate_limited" in audit_results(operator), f"audit: {audit_results(operator)}")


def check_a_machine_with_a_running_order_is_busy_and_nothing_is_changed():
    program = wrapper(OLD_TEXT)
    with remote(agent_binary=program) as (root, operator, server):
        box = box_folder()
        install(operator, server, box)
        write_wrapper(program, NEW_TEXT)
        database = sqlite3.connect(f"{root.dir}/root.sqlite3")
        database.execute("INSERT INTO commands (id, machine_id, type, params_json, state, actor, created_at) VALUES ('busy-1', 'test-box', 'create', '{}', 'running', 'x', 1)")
        database.commit()
        database.close()
        reply = operator.write("POST", UPDATE_PATH.format("test-box"), {})
        expect(reply.status == 409 and reply.body["error"]["code"] == "machine_busy", f"busy: {reply.status} {reply.raw[:200]!r}")
        expect((box / "bin" / "metaservice-agent").read_text() == OLD_TEXT, "the program must not change while an order runs")


def check_the_update_replaces_the_program_keeps_the_old_one_and_leaves_the_state_alone():
    program = wrapper(OLD_TEXT)
    with remote(agent_binary=program) as (root, operator, server):
        box = box_folder()
        install(operator, server, box)
        (box / "state" / "keep-me.txt").write_text("saved VM records stand in here")
        write_wrapper(program, NEW_TEXT)
        operator.timeout = UPDATE_REQUEST_SECONDS
        reply = operator.write("POST", UPDATE_PATH.format("test-box"), {})
        expect(reply.status == 200 and reply.body["result"] == "updated", f"update: {reply.status} {reply.raw[:300]!r}")
        expect(set(reply.body) == {"result", "message"} and "running" in reply.body["message"], f"answer: {reply.body}")
        expect((box / "bin" / "metaservice-agent").read_text() == NEW_TEXT, "the new program is in place")
        kept = box / "bin" / f"metaservice-agent.before-{sha(OLD_TEXT)[:8]}"
        expect(kept.exists() and kept.read_text() == OLD_TEXT, f"the old program is kept: {sorted(p.name for p in (box / 'bin').iterdir())}")
        expect(not (box / "bin" / "metaservice-agent.new").exists(), "no half-copied program is left")
        expect((box / "state" / "keep-me.txt").read_text() == "saved VM records stand in here" and (box / "manifest.json").exists(), "state and record are untouched")
        expect(pid_alive(box / "state" / "agent.pid"), "the helper is running again")
        expect(audit_results(operator)[0] == "updated", f"audit: {audit_results(operator)}")
        expect(sha(NEW_TEXT) not in json.dumps(operator.request("GET", "/api/audit?limit=100").body), "the audit log holds no checksum or secret")


def check_a_new_program_that_does_not_start_is_rolled_back_automatically():
    program = wrapper(OLD_TEXT)
    with remote(agent_binary=program) as (root, operator, server):
        box = box_folder()
        install(operator, server, box)
        write_wrapper(program, BROKEN_TEXT)
        operator.timeout = UPDATE_REQUEST_SECONDS
        started = time.time()
        reply = operator.write("POST", UPDATE_PATH.format("test-box"), {})
        expect(reply.status == 200 and reply.body["result"] == "rolled_back", f"rollback: {reply.status} {reply.raw[:300]!r}")
        expect(time.time() - started >= SETTLE_SECONDS, "the new program was given time to start")
        expect((box / "bin" / "metaservice-agent").read_text() == OLD_TEXT, "the old program is back")
        expect(pid_alive(box / "state" / "agent.pid"), "the old helper runs again")
        expect(audit_results(operator)[0] == "rolled_back", f"audit: {audit_results(operator)}")


def check_a_machine_that_no_longer_accepts_the_parents_key_answers_login_needed():
    program = wrapper(OLD_TEXT)
    with remote(agent_binary=program) as (root, operator, server):
        box = box_folder()
        install(operator, server, box)
        write_wrapper(program, NEW_TEXT)
        lines = pathlib.Path(server.authorized).read_text().splitlines()
        pathlib.Path(server.authorized).write_text("\n".join(line for line in lines if line.startswith("restrict")) + "\n")
        reply = operator.write("POST", UPDATE_PATH.format("test-box"), {})
        expect(reply.status == 409 and reply.body["error"]["code"] == "login_needed", f"login: {reply.status} {reply.raw[:300]!r}")
        expect((box / "bin" / "metaservice-agent").read_text() == OLD_TEXT, "nothing changed")
        expect(pid_alive(box / "state" / "agent.pid"), "the helper keeps running")


CHECKS = [check_the_update_route_is_guarded_and_knows_which_machines_exist, check_a_machine_reports_its_build_and_the_parent_says_whether_a_different_one_is_on_offer,
          check_a_hostile_build_is_refused_at_the_heartbeat, check_refusals_are_plain_409s_and_the_route_is_limited_per_machine,
          check_a_machine_with_a_running_order_is_busy_and_nothing_is_changed, check_the_update_replaces_the_program_keeps_the_old_one_and_leaves_the_state_alone,
          check_a_new_program_that_does_not_start_is_rolled_back_automatically, check_a_machine_that_no_longer_accepts_the_parents_key_answers_login_needed]
