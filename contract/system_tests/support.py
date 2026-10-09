"""A real Root with real Agents next to it, for end-to-end checks of what an operator asks and what the machines do."""
import json
import os
import sqlite3
from contextlib import contextmanager

from contract.agent_tests.support import FakeContainerWorld, FakeIncusWorld, LINUX_BINARY, RunningAgent, run_cli, wait_for, write_secret
from contract.root_tests.support import Browser, RunningRoot, expect, _free_port
from contract.tests.bundle_source import BundleSource


class Machine:
    """One enrolled Agent, started with 1-second heartbeats and a predictable budget."""

    def __init__(self, world, name, agent, container_world):
        self.world, self.name, self.agent, self.container = world, name, agent, container_world

    @property
    def command_token(self):
        return open(os.path.join(self.agent.state, "command.token")).read().strip()

    @property
    def machine_token(self):
        return open(os.path.join(self.agent.state, "agent.token")).read().strip()

    def stop_agent(self):
        self.agent.stop()

    def start_agent(self):
        self.agent.start()


class World:
    def __init__(self, root_env=None, with_bundles=False):
        self.bundles = BundleSource("unused") if with_bundles else None
        extra = ["--ui-dir", "/nonexistent-ui"] + (["--bundle-dir", str(self.bundles.dir)] if self.bundles else [])
        self.root = RunningRoot(env_text=root_env, extra_args=extra).start()
        self.operator = Browser(self.root)
        self.machines = {}

    def add_machine(self, name, engine="simulated", flavor="swift", ram_mb=20000, ram_reserve=4000, disk_gb=300, disk_reserve=10, heartbeat=1, container=None):
        invite = self.operator.write("POST", "/api/enrollments", {"name": name, "ip": "127.0.0.1"}).body["enrollment_token"]
        binary = LINUX_BINARY if flavor == "rust" else None
        agent = RunningAgent(with_token=False, binary=binary)
        token_file = os.path.join(agent.state, "enroll.token")
        write_secret(token_file, invite)
        code, _, text = run_cli(["enroll", "--root", self.root.agent_base, "--name", name, "--enrollment-token-file", token_file, "--state-dir", agent.state], binary=binary)
        expect(code == 0, f"enroll of {name} failed: {text[:150]}")
        agent.token = open(os.path.join(agent.state, "command.token")).read().strip()
        budget = ["--ram-allowance-mb", str(ram_mb), "--ram-reserve-mb", str(ram_reserve), "--disk-allowance-gb", str(disk_gb), "--disk-reserve-gb", str(disk_reserve),
                  "--heartbeat-seconds", str(heartbeat), "--chat-port", str(_free_port()), "--chat-bind", "127.0.0.1"]
        engine_args, env = [], {}
        if engine in ("apple", "incus"):
            container = container or (FakeContainerWorld() if engine == "apple" else FakeIncusWorld())
            engine_args, env = container.agent_args(), container.env
        agent.extra, agent.env = budget + engine_args, env
        agent.start()
        machine = Machine(self, name, agent, container)
        self.machines[name] = machine
        wait_for(lambda: self.view(name)["state"] == "online" and self.view(name)["free_ram_mb"] is not None, 20, f"{name} never came online")
        return machine

    def view(self, name):
        return self.operator.request("GET", f"/api/machines/{name}").body

    def create(self, **body):
        base = {"name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10}
        return self.operator.write("POST", "/api/workloads", {**base, **body})

    def wait_command(self, command_id, state="succeeded", seconds=30):
        return wait_for(lambda: (c := self.operator.request("GET", f"/api/commands/{command_id}").body["command"]) and c["state"] == state and c, seconds,
                        f"command {command_id} never became {state}")

    def make(self, **body):
        reply = self.create(**body)
        expect(reply.status == 202, f"create gave {reply.status}: {reply.raw[:200]!r}")
        command = self.wait_command(reply.body["command"]["id"])
        return command["machine"], command["result"]["workload_id"]

    def database(self):
        return sqlite3.connect(os.path.join(self.root.dir, "root.sqlite3"))

    def stop(self):
        if self.bundles:
            self.bundles.stop()
        for machine in self.machines.values():
            machine.agent.stop()
        self.root.stop()


@contextmanager
def world(**kwargs):
    made = World(**kwargs)
    try:
        yield made
    finally:
        made.stop()
