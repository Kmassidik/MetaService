"""External Docker/Incus/Apple services: strict live discovery, explicit lifecycle, command polling, audit and isolation from managed VMs."""
import json
import threading
import time
from contextlib import contextmanager
from urllib.parse import quote

from agent.fake.engine import FakeEngine, MachineSpec
from agent.fake.server import make_server
from contract.root_tests.checks_monitor import beat, enroll
from contract.root_tests.support import Browser, RunningRoot, expect, running
from contract.tests.support import Client, expect_schema

MACHINE = "mini"
PATH = f"/api/machines/{MACHINE}/external-services"
DOCKER = "docker:" + "a" * 64
INCUS = "incus:builder"
UNKNOWN = "docker:" + "0" * 64


class Helper:
    def __init__(self, token, machine_spec=None):
        self.engine = FakeEngine(machine_spec or MachineSpec())
        self.server = make_server(self.engine, token, "127.0.0.1", 0)
        self.port = self.server.server_address[1]
        self.client = Client(f"http://127.0.0.1:{self.port}", token)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


@contextmanager
def world(machine_spec=None):
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = Helper(command_token, machine_spec)
        beat(root, machine_token, helper.port)
        try:
            yield root, operator, helper
        finally:
            helper.stop()


def service_path(external_id, action=None, machine=MACHINE):
    suffix = f"/{action}" if action else ""
    return f"/api/machines/{machine}/external-services/{quote(external_id, safe='')}{suffix}"


def discover(operator):
    reply = operator.request("GET", PATH)
    expect(reply.status == 200, f"discovery gave {reply.status}: {reply.raw[:200]!r}")
    expect_schema("ExternalServiceList", reply.body, "parent discovery")
    return reply.body


def act(operator, external_id, action):
    reply = operator.write("POST", service_path(external_id, action))
    expect(reply.status == 202, f"{action} gave {reply.status}: {reply.raw[:200]!r}")
    command = reply.body["command"]
    expect(command["type"] == action and command["workload_id"] is None, f"not an external command: {command}")
    expect(command["params"] == {"external_id": external_id}, f"external id was not kept out of workload fields: {command}")
    return command


def wait(operator, command):
    deadline = time.time() + 15
    while time.time() < deadline:
        current = operator.request("GET", f"/api/commands/{command['id']}").body["command"]
        if current["state"] in ("succeeded", "failed"):
            expect(current["state"] == "succeeded", f"command failed: {current}")
            return current
        time.sleep(0.1)
    raise AssertionError(f"command did not finish: {command}")


def states(operator):
    return {service["id"]: service["state"] for service in discover(operator)["services"]}


def check_discovery_is_live_strict_and_never_adopts_or_mutates():
    with world() as (_, operator, helper):
        before = helper.engine.facts()
        body = discover(operator)
        expect(len(body["services"]) == 3 and body["warnings"] == [], f"unexpected fake discovery: {body}")
        expect(helper.engine.external_actions == [] and helper.engine.created_requests == [], "discovery caused a write")
        expect(helper.engine.facts() == before, "discovery changed resource accounting")
        machine = operator.request("GET", f"/api/machines/{MACHINE}").body
        managed = {item["id"] for item in machine["workloads"]}
        expect(managed.isdisjoint({item["id"] for item in body["services"]}), "an external service entered MachineStore.workloads")
        expect(Browser(operator.root, auto_login=False).request("GET", PATH).status == 401, "discovery without a session was accepted")
        expect(operator.request("GET", PATH, headers={"Host": "evil.example"}).status == 403, "discovery with a foreign Host was accepted")
        expect(operator.request("GET", "/api/machines/nobody/external-services").status == 404, "unknown machine was not 404")
        expect(operator.request("GET", "/api/machines/BAD%20ID/external-services").status == 404, "malformed machine id was not 404")


def check_start_stop_restart_poll_commands_and_audit_without_touching_managed_workloads():
    with world() as (_, operator, helper):
        no_session = Browser(operator.root, auto_login=False).request("POST", service_path(DOCKER, "stop"))
        expect(no_session.status == 401, "action without a session was accepted")
        expect(operator.request("POST", service_path(DOCKER, "stop")).status == 403, "action without CSRF was accepted")
        expect(operator.write("POST", service_path(DOCKER, "stop"), origin="https://evil.example").status == 403, "foreign Origin was accepted")
        expect(helper.engine.external_actions == [], "a refused action reached the helper")
        for action, expected in (("stop", "stopped"), ("start", "running"), ("restart", "running")):
            command = act(operator, DOCKER, action)
            done = wait(operator, command)
            expect(done["result"] == {"state": expected}, f"unexpected result: {done}")
            expect(states(operator)[DOCKER] == expected, f"{action} did not reach {expected}")
            expect(helper.engine.external_actions[-1]["command_id"] == command["id"], "parent did not send its command id")
        machine = operator.request("GET", f"/api/machines/{MACHINE}").body
        expect(all(item["id"] != DOCKER for item in machine["workloads"]), "lifecycle adopted Docker as managed")
        entries = operator.request("GET", "/api/audit?limit=100").body["entries"]
        requested = next(item for item in entries if item["action"] == "external_service.stop")
        finished = next(item for item in entries if item["action"] == "external_service.stop_succeeded")
        expect(json.loads(requested["detail"])["external_id"] == DOCKER and json.loads(finished["detail"])["state"] == "stopped", "audit is incomplete")
        expect(operator.write("DELETE", service_path(DOCKER)).status in (404, 405), "delete must not exist")


def check_fake_helper_command_ids_are_idempotent():
    with world() as (_, _, helper):
        path = f"/v1/external-services/{quote(INCUS, safe='')}/start"
        headers = {"X-Command-Id": "external-repeat-1"}
        first = helper.client.request("POST", path, headers=headers)
        second = helper.client.request("POST", path, headers=headers)
        expect(first.status == second.status == 202 and first.body == second.body, f"repeat differs: {first.body} {second.body}")
        expect(len(helper.engine.external_actions) == 1, "an idempotent command ran twice")
        done = helper.client.request("GET", "/v1/commands/external-repeat-1")
        expect(done.status == 200, f"command lookup gave {done.status}")
        expect_schema("Command", done.body, "external command")
        expect(done.body["type"] == "start" and "workload_id" not in done.body, f"external command looked managed: {done.body}")


def check_unknown_old_unreachable_and_malformed_helpers_preserve_errors_without_commands():
    with world() as (_, operator, helper):
        reply = operator.write("POST", service_path(UNKNOWN, "start"))
        expect(reply.status == 404, f"unknown target gave {reply.status}: {reply.body}")
        expect(operator.request("GET", "/api/commands").body["commands"] == [], "unknown target left a command")
        expect(helper.engine.external_actions == [], "unknown target reached a lifecycle")
    with world(MachineSpec(serves_external_services=False)) as (_, operator, _):
        expect(operator.request("GET", PATH).status == 404, "old helper discovery was not preserved as 404")
        expect(operator.write("POST", service_path(DOCKER, "start")).status == 404, "old helper action was not 404")
    with world(MachineSpec(external_services=[{"id": DOCKER, "name": "bad", "runtime": "docker", "kind": "container", "state": "running", "extra": True}])) as (_, operator, _):
        expect(operator.request("GET", PATH).status == 502, "a malformed helper answer was not a 502")
    with running() as root:
        operator = Browser(root)
        enroll(operator, MACHINE)
        expect(operator.request("GET", PATH).status == 502, "unreachable discovery was not a 502")
        expect(operator.write("POST", service_path(DOCKER, "start")).status == 502, "unreachable action was not a 502")
        expect(operator.request("GET", "/api/commands").body["commands"] == [], "an unreachable target left a command")


def check_an_unfinished_external_command_resumes_after_a_root_restart():
    root = RunningRoot().start()
    restarted = None
    helper = None
    try:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = Helper(command_token)
        beat(root, machine_token, helper.port)
        helper.engine.external_defer = True
        command = act(operator, INCUS, "start")
        expect(command["state"] == "running", f"deferred command was not running: {command}")
        root.stop()
        restarted = RunningRoot()
        restarted.dir = root.dir
        restarted.env_file = root.env_file
        restarted.start()
        operator = Browser(restarted)
        helper.engine.complete_external(command["id"])
        done = wait(operator, command)
        expect(done["result"] == {"state": "running"}, f"resumed command has wrong result: {done}")
        expect(len(helper.engine.external_actions) == 1, "resume sent the lifecycle a second time")
    finally:
        if restarted is not None:
            restarted.stop()
        root.stop()
        if helper is not None:
            helper.stop()


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
