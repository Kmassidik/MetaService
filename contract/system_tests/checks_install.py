"""Add machine, as the form does it: install MetaService on the control plane's own computer, with or without the chat, with a real Agent."""
import os
import stat
from contextlib import contextmanager

from contract.agent_tests.support import MACOS_BINARY, wait_for
from contract.root_tests.support import Browser, RunningRoot, _free_port, _port_open, expect
from contract.tests.bundle_source import BundleSource


@contextmanager
def install_root(with_bundles=False, binary=None):
    agent_port, chat_port = _free_port(), _free_port()
    bundles = BundleSource("unused") if with_bundles else None
    extra = ["--ui-dir", "/nonexistent-ui", "--agent-binary", str(binary or MACOS_BINARY), "--local-agent-port", str(agent_port), "--local-chat-port", str(chat_port)]
    if bundles:
        extra += ["--bundle-dir", str(bundles.dir)]
    root = RunningRoot(extra_args=extra).start()
    root.local_agent_port, root.local_chat_port = agent_port, chat_port
    try:
        yield root, Browser(root)
    finally:
        root.stop()
        if bundles:
            bundles.stop()


def body(**changes):
    return {"target": "this", "name": "this-mac", "chat": False, **changes}


def install(operator, **changes):
    reply = operator.write("POST", "/api/installs", body(**changes))
    expect(reply.status == 202, f"install gave {reply.status}: {reply.raw[:160]!r}")
    return reply.body["id"]


def finished(operator, job_id, seconds=120):
    return wait_for(lambda: (j := operator.request("GET", f"/api/installs/{job_id}").body) and j["state"] in ("done", "failed") and j, seconds, f"install {job_id} never finished")


def check_the_form_gets_a_name_and_sensible_limits_and_needs_a_login():
    with install_root() as (root, operator):
        expect(Browser(root, auto_login=False).request("GET", "/api/installs/defaults").status == 401, "the defaults are open without a login")
        defaults = operator.request("GET", "/api/installs/defaults").body
        expect(set(defaults) == {"name", "ram_reserve_mb", "disk_reserve_gb", "agent_ready", "chat_available"}, f"keys: {sorted(defaults)}")
        expect(defaults["name"] and defaults["ram_reserve_mb"] >= 1024 and defaults["disk_reserve_gb"] >= 1, f"defaults: {defaults}")
        expect(defaults["agent_ready"] is True and defaults["chat_available"] is False, f"readiness: {defaults}")
        expect(operator.request("GET", "/api/machines").body["machines"] == [], "a new control plane must start with 0 machines installed")


def check_bad_requests_and_a_missing_program_are_refused_and_nothing_is_created():
    with install_root() as (root, operator):
        for label, change in [("another computer", {"target": "10.0.0.5"}), ("bad name", {"name": "Bad Name"}), ("chat as text", {"chat": "yes"}),
                              ("negative ram", {"ram_reserve_mb": -1}), ("unknown field", {"root": True})]:
            reply = operator.write("POST", "/api/installs", body(**change))
            expect(reply.status == 400, f"{label}: {reply.status}")
        expect(operator.request("POST", "/api/installs", body(), headers={"X-CSRF-Token": "x" * 43}).status == 403, "an install without the right CSRF token")
        expect(operator.request("GET", "/api/installs/in-nothing").status == 404, "an unknown install was not a 404")
        expect(operator.request("GET", "/api/machines").body["machines"] == [], "a refused install created a machine")
    with install_root(binary="/nonexistent/agent") as (root, operator):
        reply = operator.write("POST", "/api/installs", body())
        expect(reply.status == 409 and reply.body["error"]["code"] == "agent_missing", f"missing program: {reply.status} {reply.body}")
        expect(operator.request("GET", "/api/installs/defaults").body["agent_ready"] is False, "the form should know the program is missing")


def check_an_install_without_the_chat_starts_the_agent_and_the_machine_reports_in():
    with install_root() as (root, operator):
        job = finished(operator, install(operator))
        expect(job["state"] == "done" and [s["id"] for s in job["steps"]] == ["check", "agent", "online"], f"job: {job}")
        expect(all(s["state"] == "done" for s in job["steps"]), f"steps: {job['steps']}")
        machines = operator.request("GET", "/api/machines").body["machines"]
        expect([m["name"] for m in machines] == ["this-mac"] and machines[0]["state"] != "offline", f"machines: {machines}")
        expect(machines[0]["bundle_version"] is None, "the chat was installed although it was not asked for")
        expect(bool(job["warning"]) == bool(machines[0]["problems"]), f"the job should warn exactly when the machine reports a problem: {job.get('warning')} / {machines[0]['problems']}")
        folder = os.path.join(root.dir, "agents", "this-mac")
        expect(not os.path.exists(os.path.join(folder, "enroll.token")), "the one-time invite file was left behind")
        expect(stat.S_IMODE(os.stat(os.path.join(folder, "agent.token")).st_mode) == 0o600, "the Agent's token file is not private")
        again = operator.write("POST", "/api/installs", body())
        expect(again.status == 409 and again.body["error"]["code"] == "machine_exists", f"a second install of the same name: {again.status}")
        actions = [e["action"] for e in operator.request("GET", "/api/audit").body["entries"]]
        expect("machine.install" in actions and "machine.enroll" in actions, f"audit: {actions[:6]}")


def check_an_install_with_the_chat_also_installs_the_chat_and_pins_a_version():
    with install_root(with_bundles=True) as (root, operator):
        expect(operator.request("GET", "/api/installs/defaults").body["chat_available"] is True, "the form should know a chat bundle exists")
        job = finished(operator, install(operator, chat=True))
        expect(job["state"] == "done" and [s["id"] for s in job["steps"]] == ["check", "agent", "online", "chat"], f"job: {job}")
        wait_for(lambda: operator.request("GET", "/api/machines/this-mac").body["bundle_version"], 20, "the machine never showed the chat version")
        expect(operator.request("GET", "/api/bundles").body["pinned"] is not None, "no chat version was pinned")
        expect(operator.request("GET", "/api/chat-link?machine=this-mac").status == 200, "no chat link for the machine")


def check_an_install_with_the_chat_fails_clearly_when_there_is_no_chat_bundle():
    with install_root() as (root, operator):
        job = finished(operator, install(operator, chat=True))
        expect(job["state"] == "failed" and "chat bundle" in job["error"], f"job: {job}")
        expect([s["state"] for s in job["steps"]] == ["done", "done", "done", "failed"], f"steps: {job['steps']}")


def check_the_agent_stops_with_the_control_plane_and_comes_back_when_it_starts_again():
    with install_root() as (root, operator):
        finished(operator, install(operator))
        expect(_port_open(root.local_agent_port), "the Agent is not listening after the install")
        root.stop()
        wait_for(lambda: not _port_open(root.local_agent_port), 10, "the Agent kept running after the control plane stopped")
        root.start()
        wait_for(lambda: _port_open(root.local_agent_port), 20, "the Agent was not started again with the control plane")
        again = Browser(root)
        wait_for(lambda: again.request("GET", "/api/machines").body["machines"][0]["state"] != "offline", 40, "the machine did not report in again")


CHECKS = [check_the_form_gets_a_name_and_sensible_limits_and_needs_a_login, check_bad_requests_and_a_missing_program_are_refused_and_nothing_is_created,
          check_an_install_without_the_chat_starts_the_agent_and_the_machine_reports_in, check_an_install_with_the_chat_also_installs_the_chat_and_pins_a_version,
          check_an_install_with_the_chat_fails_clearly_when_there_is_no_chat_bundle, check_the_agent_stops_with_the_control_plane_and_comes_back_when_it_starts_again]
