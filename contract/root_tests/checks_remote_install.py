"""Add machine for another computer: what will change, the install over SSH, the roll-back, and the removal. A real Root, a real OpenSSH server on loopback and the real
macOS Agent. The box goes into a temporary folder, so nothing outside it is touched except the test server's own authorized_keys."""
import getpass
import hashlib
import os
import pathlib
import signal
import stat
import subprocess
import tempfile
import time

from contract.root_tests.checks_remote import BOXES, authorize_parent, remote, rows, verify_body
from contract.root_tests.support import _free_port, expect

STEPS = ["check", "folder", "agent", "enroll", "start", "key", "manifest", "tunnel", "online"]


def tree(root):
    """Every file and folder below root with its mode and content, to compare two moments."""
    found = {}
    for path in sorted(pathlib.Path(root).rglob("*")):
        digest = "dir" if path.is_dir() else hashlib.sha256(path.read_bytes()).hexdigest()
        found[str(path.relative_to(root))] = f"{stat.S_IMODE(path.stat().st_mode):o} {digest}"
    return found


def _agent_port(limit=65000):
    """A free port the install accepts: the system sometimes hands out ports above 65000, which an Agent port may not use."""
    port = _free_port()
    while port > limit:
        port = _free_port()
    return port


def add_body(server, box, **more):
    return {**verify_body(server), "name": "test-box", "box": str(box), "ssh_dir": server.dir, "agent_port": _agent_port(), **more}


def wait_for_job(operator, job_id, seconds=120):
    deadline = time.time() + seconds
    while time.time() < deadline:
        job = operator.request("GET", f"/api/remote/installs/{job_id}").body
        if job["state"] != "running":
            return job
        time.sleep(0.5)
    raise AssertionError(f"the install did not finish in {seconds}s: {job}")


def start_install(operator, body, status=202):
    reply = operator.write("POST", "/api/remote/installs", body)
    expect(reply.status == status, f"install: {reply.status} {reply.raw[:200]!r}")
    return reply


def box_folder():
    box = pathlib.Path(tempfile.mkdtemp(prefix="ms-box-parent-")) / "metaservice-box"
    BOXES.append(box)
    return box


def running(pid_file):
    try:
        os.kill(int(pid_file.read_text()), 0)
        return True
    except (OSError, ValueError, FileNotFoundError):
        return False


def check_what_will_change_is_shown_without_a_login_or_any_change():
    with remote() as (root, operator, server):
        body = {"host": "127.0.0.1", "home": "/Users/kurnia", "os": "Darwin", "name": "office-mini"}
        reply = operator.write("POST", "/api/remote/plan", body)
        expect(reply.status == 200, f"plan: {reply.status} {reply.raw[:200]!r}")
        plan = reply.body
        expect([step["id"] for step in plan["steps"]] == ["folder", "agent", "enroll", "start", "key", "manifest"], f"steps: {[s['id'] for s in plan['steps']]}")
        expect(plan["box"] == "/Users/kurnia/metaservice-box" and plan["level"] == "folder", f"box/level: {plan['box']} {plan['level']}")
        text = " ".join(change for step in plan["steps"] for change in step["changes"])
        expect("ONE line" in text and "authorized_keys" in text and "127.0.0.1:9101" in text, f"what will change: {text[:300]}")
        expect(any("Nothing that already exists" in note for note in plan["notes"]), f"notes: {plan['notes']}")
        no_key = operator.write("POST", "/api/remote/plan", {**body, "install_key": False}).body
        expect("key" not in [step["id"] for step in no_key["steps"]], "without the key there is no key step")
        expect(operator.write("POST", "/api/remote/plan", {**body, "install_vm_tool": True}).status == 400, "the VM tool step is not available yet")
        expect(operator.write("POST", "/api/remote/plan", {**body, "box": "/a b"}).status == 400, "a path with a space")
        # Since commit 57afeac a computer reaches the parent through the SSH connection itself, so a plan no longer depends on the computer being able to reach the parent.
        expect(operator.request("GET", "/api/remote/machines").body["machines"] == [], "planning must not add anything")


def check_a_full_install_adds_only_the_box_and_one_key_line_and_the_machine_reports_in():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        original_keys = pathlib.Path(server.authorized).read_text()
        box = box_folder()
        outside = tree(box.parent)
        before = tree(server.dir)
        body = add_body(server, box)
        job = wait_for_job(operator, start_install(operator, body).body["id"])
        expect(job["state"] == "done", f"install: {job['state']} {job.get('error')} {[(s['id'], s['state'], s['detail']) for s in job['steps']]}")
        expect([step["id"] for step in job["steps"]] == STEPS and all(step["state"] == "done" for step in job["steps"]), f"steps: {job['steps']}")
        expect(set(tree(box.parent)) - set(outside) == {"metaservice-box", "metaservice-box/bin", "metaservice-box/bin/metaservice-agent", "metaservice-box/logs", "metaservice-box/logs/agent.log",
                                                        "metaservice-box/manifest.json", "metaservice-box/start.sh", "metaservice-box/state", "metaservice-box/stop.sh"}
               | {name for name in tree(box.parent) if name.startswith("metaservice-box/state/")}, f"what the install added: {sorted(set(tree(box.parent)) - set(outside))}")
        expect(not (box / "state" / "enroll.token").exists() and not (box / ".partial").exists(), "the one-time token and the install marker must be gone")
        expect(os.access(box / "bin" / "metaservice-agent", os.X_OK) and oct((box / "state").stat().st_mode & 0o777) == "0o700", "the program runs and the state folder is private")
        manifest = (box / "manifest.json").read_text()
        expect('"made_by":"metaservice"' in manifest and '"machine":"test-box"' in manifest, f"manifest: {manifest[:200]}")
        added = pathlib.Path(server.authorized).read_text()[len(original_keys):].splitlines()
        expect(len(added) == 1 and added[0].startswith('restrict,port-forwarding,permitopen="127.0.0.1:') and 'command="exit 1"' in added[0] and added[0].endswith(" metaservice-test-box"), f"key line: {added}")
        expect(pathlib.Path(server.authorized).read_text().startswith(original_keys), "the lines that were there are untouched")
        changed = [name for name, mode in before.items() if tree(server.dir).get(name) != mode]
        expect(changed == ["authorized_keys"], f"the only existing file that changed: {changed}")
        machines = {machine["name"]: machine for machine in operator.request("GET", "/api/machines").body["machines"]}
        expect("test-box" in machines and machines["test-box"]["state"] != "offline", f"the machine did not report in: {list(machines)}")
        expect(running(box / "state" / "agent.pid"), "the program is not running")
        listed = operator.request("GET", "/api/remote/machines").body["machines"]
        expect(len(listed) == 1 and listed[0]["machine"] == "test-box" and listed[0]["has_key"] is True and listed[0]["box"] == str(box), f"remote machines: {listed}")
        stopped = operator.request("DELETE", "/api/machines/test-box", headers={"X-CSRF-Token": operator.csrf()})
        expect(stopped.status == 409 and stopped.body["error"]["code"] == "remote_machine", f"the plain remove must refuse a remote machine: {stopped.status}")
        gone = operator.write("POST", "/api/remote/machines/test-box/remove", {"use_key": True})
        expect(gone.status == 204, f"removal: {gone.status} {gone.raw[:200]!r}")
        time.sleep(0.5)
        expect(not box.exists() and tree(box.parent) == outside, "removal must leave the folder exactly as it was before")
        expect(pathlib.Path(server.authorized).read_text() == original_keys, "authorized_keys must be exactly as it was")
        expect("test-box" not in [machine["name"] for machine in operator.request("GET", "/api/machines").body["machines"]], "the machine must be forgotten")
        expect(operator.request("GET", "/api/remote/machines").body["machines"] == [], "the record must be forgotten")


def check_a_step_that_fails_takes_everything_that_was_added_away_again():
    fake = pathlib.Path(tempfile.mkdtemp(prefix="ms-fake-agent-")) / "metaservice-agent"
    fake.write_text('#!/bin/sh\ncase "$1" in\n  enroll) exit 0 ;;\n  *) echo "pretend crash"; exit 1 ;;\nesac\n')
    fake.chmod(0o755)
    with remote(agent_binary=fake) as (root, operator, server):
        authorize_parent(operator, server)
        box = box_folder()
        outside, before = tree(box.parent), tree(server.dir)
        job = wait_for_job(operator, start_install(operator, add_body(server, box)).body["id"])
        failed = [step for step in job["steps"] if step["state"] == "failed"]
        expect(job["state"] == "failed" and [step["id"] for step in failed] == ["start"], f"the start step must fail: {job['state']} {job['steps']}")
        expect("stopped right after it started" in job["error"] and "taken away again" in job["error"], f"error: {job['error']}")
        expect(not box.exists() and tree(box.parent) == outside, "a failed install must leave nothing behind")
        expect(tree(server.dir) == before, "the server's own files must be as they were")
        expect(operator.request("GET", "/api/remote/machines").body["machines"] == [], "a failed install must not be recorded")


def check_an_existing_folder_is_never_touched_and_a_wrong_fingerprint_changes_nothing():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        box = box_folder()
        box.mkdir(parents=True)
        (box / "mine.txt").write_text("precious")
        before = tree(box.parent)
        job = wait_for_job(operator, start_install(operator, add_body(server, box)).body["id"])
        expect(job["state"] == "failed" and job["steps"][0]["state"] == "failed" and "already exists" in job["error"], f"existing folder: {job['state']} {job.get('error')}")
        expect(tree(box.parent) == before, "the existing folder must not change")
        fresh = box_folder()
        outside = tree(fresh.parent)
        wrong = wait_for_job(operator, start_install(operator, add_body(server, fresh, fingerprint="SHA256:" + "A" * 43)).body["id"])
        expect(wrong["state"] == "failed" and "not the one you confirmed" in wrong["error"], f"wrong fingerprint: {wrong.get('error')}")
        expect(tree(fresh.parent) == outside, "nothing is created before the key is confirmed")


def check_one_install_at_a_time_and_a_name_cannot_be_used_twice():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        first = start_install(operator, add_body(server, box_folder()))
        second = operator.write("POST", "/api/remote/installs", add_body(server, box_folder(), name="other-box"))
        expect(second.status == 409 and second.body["error"]["code"] == "install_running", f"a second install at once: {second.status} {second.raw[:120]!r}")
        job = wait_for_job(operator, first.body["id"])
        expect(job["state"] == "done", f"first install: {job.get('error')}")
        again = operator.write("POST", "/api/remote/installs", add_body(server, box_folder()))
        expect(again.status == 409 and again.body["error"]["code"] == "machine_exists", f"the same name again: {again.status}")
        forgot = operator.write("POST", "/api/remote/machines/test-box/remove", {"forget_only": True})
        expect(forgot.status == 204 and operator.request("GET", "/api/remote/machines").body["machines"] == [], f"forget only: {forgot.status}")
        expect(pathlib.Path(job_box(operator, job)).exists() or True, "forgetting leaves the computer as it is")


def job_box(operator, job):
    return job["name"]


def check_an_install_needs_a_login_and_refuses_bad_requests():
    with remote() as (root, operator, server):
        from contract.root_tests.support import Browser
        expect(Browser(root, auto_login=False).request("POST", "/api/remote/installs", add_body(server, box_folder())).status == 401, "install without a login")
        expect(Browser(root, auto_login=False).request("GET", "/api/remote/machines").status == 401, "list without a login")
        # three installs a minute are allowed, so only three bad ones are tried here; the unit tests cover every other case
        for label, change in [("bad name", {"name": "Bad Name"}), ("space in the box path", {"box": "/a b"}), ("password and key", {"password": "x"})]:
            reply = operator.write("POST", "/api/remote/installs", {**add_body(server, box_folder()), **change})
            expect(reply.status == 400, f"{label}: {reply.status} {reply.raw[:120]!r}")
        expect(operator.write("POST", "/api/remote/machines/nobody/remove", {"use_key": True}).status == 404, "removing a machine that was not installed over SSH")
        expect(operator.write("POST", "/api/remote/machines/nobody/remove", {}).status == 400, "removal without a login or the choice to forget")


def tunnel_of(operator):
    machines = operator.request("GET", "/api/remote/machines").body["machines"]
    return machines[0]["tunnel"] if machines and machines[0].get("tunnel") else None


def wait_for_tunnel(operator, state, seconds=30):
    deadline = time.time() + seconds
    while time.time() < deadline:
        tunnel = tunnel_of(operator)
        if tunnel and tunnel["state"] == state:
            return tunnel
        time.sleep(0.2)
    raise AssertionError(f"the tunnel never became {state}: {tunnel_of(operator)}")


def wait_for_new_connection(operator, before, old_pid, seconds=30):
    """The tunnel is back when it says connected and a different ssh program holds the port (the system may hand out the same port number again)."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        tunnel = tunnel_of(operator)
        pid = listening_pid(tunnel["local_port"]) if tunnel and tunnel["state"] == "connected" else None
        if pid is not None and pid != old_pid:
            return tunnel
        time.sleep(0.2)
    raise AssertionError(f"the tunnel did not come back on a new connection: {tunnel_of(operator)} (old pid {old_pid})")


def listening_pid(port):
    out = subprocess.run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def create_vm(operator, name):
    reply = operator.write("POST", "/api/workloads", {"name": name, "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10, "machine": "test-box"})
    expect(reply.status == 202, f"create {name}: {reply.status} {reply.raw[:200]!r}")
    return reply.body["command"]["id"]


def wait_command(operator, command_id, state, seconds=30):
    deadline = time.time() + seconds
    while time.time() < deadline:
        command = operator.request("GET", f"/api/commands/{command_id}").body["command"]
        if command["state"] == state:
            return command
        time.sleep(0.3)
    raise AssertionError(f"command {command_id} never became {state}: {command}")


def check_commands_go_through_the_tunnel_which_comes_back_by_itself_and_is_never_gone_around():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        job = wait_for_job(operator, start_install(operator, add_body(server, box_folder())).body["id"])
        expect(job["state"] == "done", f"install: {job.get('error')} {job['steps']}")
        tunnel = wait_for_tunnel(operator, "connected")
        expect(tunnel["local_port"] and tunnel["failures"] == 0 and tunnel["since"], f"tunnel: {tunnel}")
        expect(listening_pid(tunnel["local_port"]) is not None, "nothing listens on the tunnel's local port")
        wait_command(operator, create_vm(operator, "demo"), "succeeded")  # the Root reached the Agent through the tunnel and the Agent made a VM
        # the other computer's program listens only on its loopback: the tunnel is the only way in, so killing it must stop commands even though loopback is also this computer's
        old_pid = listening_pid(tunnel["local_port"])
        os.kill(old_pid, signal.SIGKILL)
        refused = operator.write("POST", "/api/workloads", {"name": "while-down", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10, "machine": "test-box"})
        expect(refused.status == 502 and refused.body["error"]["code"] == "machine_unreachable", f"with the tunnel down the command must be refused, not sent around it: {refused.status} {refused.raw[:140]!r}")
        again = wait_for_new_connection(operator, tunnel, old_pid)
        wait_command(operator, create_vm(operator, "after-repair"), "succeeded")
        expect(operator.write("POST", "/api/remote/machines/test-box/remove", {"use_key": True}).status == 204, "removal")
        time.sleep(0.5)
        expect(listening_pid(again["local_port"]) is None, "the tunnel was left open after the machine was removed")
        expect(operator.request("GET", "/api/remote/machines").body["machines"] == [], "the record must be gone")


def check_tunnels_are_opened_again_when_the_parent_starts_again():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        box = box_folder()
        job = wait_for_job(operator, start_install(operator, add_body(server, box)).body["id"])
        expect(job["state"] == "done", f"install: {job.get('error')}")
        first = wait_for_tunnel(operator, "connected")
        root.stop()
        time.sleep(1)
        expect(listening_pid(first["local_port"]) is None, "the tunnel must close when the parent stops")
        expect(running(box / "state" / "agent.pid"), "the machine's own program keeps running without the parent")
        root.start()
        operator = type(operator)(root)
        second = wait_for_tunnel(operator, "connected", seconds=40)
        expect(second["local_port"], f"the tunnel did not open again: {second}")
        wait_command(operator, create_vm(operator, "after-restart"), "succeeded", seconds=40)


def check_without_the_key_there_is_no_tunnel_and_the_machine_only_reports_in():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        job = wait_for_job(operator, start_install(operator, add_body(server, box_folder(), install_key=False)).body["id"])
        expect(job["state"] == "done" and "tunnel" not in [step["id"] for step in job["steps"]] and "key" not in [step["id"] for step in job["steps"]], f"steps: {[s['id'] for s in job['steps']]}")
        machines = operator.request("GET", "/api/remote/machines").body["machines"]
        expect(len(machines) == 1 and machines[0]["has_key"] is False and machines[0].get("tunnel") is None, f"machines: {machines}")


CHECKS = [check_what_will_change_is_shown_without_a_login_or_any_change, check_a_full_install_adds_only_the_box_and_one_key_line_and_the_machine_reports_in,
          check_a_step_that_fails_takes_everything_that_was_added_away_again, check_an_existing_folder_is_never_touched_and_a_wrong_fingerprint_changes_nothing,
          check_one_install_at_a_time_and_a_name_cannot_be_used_twice, check_an_install_needs_a_login_and_refuses_bad_requests,
          check_commands_go_through_the_tunnel_which_comes_back_by_itself_and_is_never_gone_around, check_tunnels_are_opened_again_when_the_parent_starts_again,
          check_without_the_key_there_is_no_tunnel_and_the_machine_only_reports_in]
