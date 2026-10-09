"""Add machine, as the form does it: install MetaService on the control plane's own computer, with or without the chat, with a real Agent."""
import os
import stat
from contextlib import contextmanager

from contract.agent_tests.support import MACOS_BINARY, wait_for
from contract.root_tests.support import Browser, RunningRoot, _free_port, _port_open, expect
from contract.tests.bundle_source import BundleSource


@contextmanager
def install_root(with_bundles=False, binary=None, cwd=None):
    agent_port, chat_port = _free_port(), _free_port()
    bundles = BundleSource("unused") if with_bundles else None
    extra = ["--ui-dir", "/nonexistent-ui", "--agent-binary", str(binary or MACOS_BINARY), "--local-agent-port", str(agent_port), "--local-chat-port", str(chat_port)]
    if bundles:
        extra += ["--bundle-dir", str(bundles.dir)]
    root = RunningRoot(extra_args=extra, cwd=cwd).start()
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
        expect(set(defaults) - {"ai_model"} == {"name", "ram_reserve_mb", "disk_reserve_gb", "agent_ready", "chat_available", "profile", "computer", "vm_cpu", "vm_ram_mb", "vm_disk_gb"}, f"keys: {sorted(defaults)}")
        expect(set(defaults["computer"]) == {"name", "os", "arch", "cpu_cores", "ram_mb", "disk_gb"} and defaults["computer"]["cpu_cores"] >= 1, f"computer: {defaults['computer']}")
        expect("ai_model" not in defaults, "no AI provider is set up here, so there is no model to suggest")
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


def check_an_install_works_when_the_program_is_given_as_a_path_from_the_folder_the_control_plane_starts_in():
    """How the run script starts it: from control-plane/arm64, with the Agent at ../../agent/macos/... (this once failed with 'the file does not exist')."""
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    relative = "../../agent/macos/" + os.path.relpath(str(MACOS_BINARY), os.path.join(repo, "agent", "macos"))
    with install_root(binary=relative, cwd=os.path.join(repo, "control-plane", "arm64")) as (root, operator):
        job = finished(operator, install(operator, name="rel-path"))
        expect(job["state"] == "done", f"install: {job['state']} {job.get('error')}")


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


SETTINGS = {"profile": "apple-silicon-mac", "labels": ["office", "desk"], "notes": "on the desk", "ram_reserve_mb": 4096, "disk_reserve_gb": 30, "ram_allowance_mb": 12288,
            "disk_allowance_gb": 400, "allow_gpu": False, "vm_cpu": 2, "vm_ram_mb": 4096, "vm_disk_gb": 40, "vm_image": "images:ubuntu/24.04", "vm_max_running": 3,
            "subdomain": "mac1", "public_chat": True, "ai_model": "vendor/some-model"}


def check_the_settings_from_the_form_are_kept_shown_and_applied_to_the_agent():
    with install_root() as (root, operator):
        job = finished(operator, install(operator, **SETTINGS))
        expect(job["state"] == "done", f"job: {job}")
        shown = operator.request("GET", "/api/machines/this-mac").body["settings"]
        expect(shown == SETTINGS | {"ram_reserve_mb": 4096}, f"settings: {shown}")
        facts = wait_for(lambda: Browser(root).request("GET", "/api/machines/this-mac").body, 15, "no facts")
        expect(facts["free_ram_mb"] is not None and facts["free_ram_mb"] <= 12288, f"the memory allowance was not applied: {facts['free_ram_mb']}")
        expect(facts["free_disk_gb"] <= 400, f"the disk allowance was not applied: {facts['free_disk_gb']}")
        expect(operator.request("GET", "/api/machines").body["machines"][0]["settings"]["labels"] == ["office", "desk"], "the list does not carry the labels")


def check_bad_settings_are_refused_and_nothing_is_installed():
    with install_root() as (root, operator):
        for label, change in [("unknown profile", {"profile": "toaster"}), ("label with a space", {"labels": ["a b"]}), ("reserve above allowance", {"ram_reserve_mb": 9000, "ram_allowance_mb": 4096}),
                              ("flag as an image", {"vm_image": "--privileged"}), ("subdomain with a dot", {"subdomain": "a.b"})]:  # five tries: the route allows five a minute
            reply = operator.write("POST", "/api/installs", body(**change))
            expect(reply.status == 400, f"{label}: {reply.status}")
        expect(operator.request("GET", "/api/machines").body["machines"] == [], "a refused install created a machine")
        expect(not _port_open(root.local_agent_port), "a refused install started an Agent")


def check_removing_an_installed_machine_stops_its_agent_and_forgets_its_settings():
    with install_root() as (root, operator):
        finished(operator, install(operator, **SETTINGS))
        expect(_port_open(root.local_agent_port), "the Agent is not running after the install")
        removed = operator.write("DELETE", "/api/machines/this-mac")
        expect(removed.status == 204, f"remove gave {removed.status}")
        wait_for(lambda: not _port_open(root.local_agent_port), 10, "the Agent kept running after its machine was removed")
        expect(operator.request("GET", "/api/machines").body["machines"] == [], "the machine is still listed")
        root.stop()
        root.start()
        import time
        time.sleep(3)
        expect(not _port_open(root.local_agent_port), "a removed machine's Agent was started again with the control plane")
        again = finished(Browser(root), install(Browser(root), name="this-mac"))
        expect(again["state"] == "done", "the name could not be used again after removal")


CHECKS = [check_the_form_gets_a_name_and_sensible_limits_and_needs_a_login, check_bad_requests_and_a_missing_program_are_refused_and_nothing_is_created,
          check_an_install_without_the_chat_starts_the_agent_and_the_machine_reports_in, check_an_install_with_the_chat_also_installs_the_chat_and_pins_a_version,
          check_an_install_with_the_chat_fails_clearly_when_there_is_no_chat_bundle, check_an_install_works_when_the_program_is_given_as_a_path_from_the_folder_the_control_plane_starts_in, check_the_settings_from_the_form_are_kept_shown_and_applied_to_the_agent,
          check_bad_settings_are_refused_and_nothing_is_installed, check_removing_an_installed_machine_stops_its_agent_and_forgets_its_settings, check_the_agent_stops_with_the_control_plane_and_comes_back_when_it_starts_again]
