"""The helper's console: GET /v1/workloads/{id}/terminal as a WebSocket. Runs against the real macOS helper (simulated engine) or, with
`python -m contract.agent_tests.runner --fake`, against the Fake Agent. Both must pass the same checks."""
import os
import re
import secrets
import threading
import time
from contextlib import contextmanager

from contract import wsproto
from contract.agent_tests.support import agent
from contract.root_tests.support import expect, _free_port

MAX_FRAME = 65536
WAIT_SECONDS = 10


class FakeHelper:
    """The Fake Agent on a free port, shaped like RunningAgent for the parts these checks use."""

    def __init__(self, stats=None, sandbox=False):
        from agent.fake.engine import FakeEngine, MachineSpec
        from agent.fake.server import make_server
        self.token = secrets.token_hex(24)
        self.server = make_server(FakeEngine(MachineSpec(sandbox=sandbox)), self.token, "127.0.0.1", _free_port(), stats)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def call(self, method, path, body=None, token="default"):
        import http.client
        import json
        headers = {} if token is None else {"Authorization": f"Bearer {self.token if token == 'default' else token}"}
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=15)
        connection.request(method, path, body=None if body is None else json.dumps(body), headers={**headers, "Content-Type": "application/json"})
        response = connection.getresponse()
        raw = response.read()
        connection.close()
        return response.status, (json.loads(raw) if raw else None)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


@contextmanager
def helper():
    if os.environ.get("MS_HELPER") == "fake":
        one = FakeHelper()
        try:
            yield one
        finally:
            one.stop()
    else:
        with agent() as one:
            yield one


def make_vm(one, name="vm1", stop=False):
    status, accepted = one.call("POST", "/v1/workloads", {"command_id": f"c-{name}", "name": name, "kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1})
    expect(status == 202, f"create gave {status} {accepted}")
    status, command = one.call("GET", f"/v1/commands/c-{name}")
    workload = command.get("workload_id") or command["result"]["workload_id"]
    if stop:
        expect(one.call("POST", f"/v1/workloads/{workload}/stop")[0] == 202, "stop was not accepted")
    return workload


def open_console(one, workload, token="default"):
    use = one.token if token == "default" else token
    headers = {} if use is None else {"Authorization": f"Bearer {use}"}
    return wsproto.Client.connect(one.port, f"/v1/workloads/{workload}/terminal", headers)


def shell_pid(client):
    """Types a sum that only the shell's answer contains, and returns the shell's process id (the helper and the checks share a host)."""
    client.send_binary(b"echo pid=$((1000000+$$))\n")
    seen = client.read_until(re.compile(rb"pid=1\d{6}\r?\n"), WAIT_SECONDS)
    return int(re.findall(rb"pid=1(\d{6})\r?\n", seen)[-1])


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def wait_gone(pid, seconds=WAIT_SECONDS):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if not alive(pid):
            return True
        time.sleep(0.1)
    return False


def refused(reply):
    return isinstance(reply, wsproto.Refusal) and reply.status != 101


def expect_exact(one, vm, token, status, code):
    """The exact answer from a plain GET without upgrade headers (the library answers a refused upgrade with a bare 400)."""
    got, body = one.call("GET", f"/v1/workloads/{vm}/terminal", token=token)
    found = ((body or {}).get("error") or {}).get("code")
    expect(got == status and (code is None or found == code), f"plain GET {vm} token {token!r}: {got} {body}")


def check_the_console_needs_the_command_token_and_a_real_running_workload():
    with helper() as one:
        vm = make_vm(one)
        stopped = make_vm(one, "vm2", stop=True)
        for token in (None, "wrong-token"):
            expect(refused(open_console(one, vm, token=token)), f"token {token!r}: the upgrade was not refused")
            expect_exact(one, vm, token, 401, None)
        for label, target, status, code in (("unknown workload", "no-such-vm", 404, "not_found"), ("stopped workload", stopped, 409, "not_running")):
            expect(refused(open_console(one, target)), f"{label}: the upgrade was not refused")
            expect_exact(one, target, "default", status, code)
        expect(refused(open_console(one, "Bad_Id")), "a bad id: the upgrade was not refused")
        expect_exact(one, vm, "default", 426, None)


def check_you_can_type_into_the_shell_and_read_the_answer():
    with helper() as one:
        client = open_console(one, make_vm(one))
        expect(isinstance(client, wsproto.Client), f"upgrade refused: {getattr(client, 'status', None)}")
        try:
            client.send_binary(b"echo hel\"\"lo-$((20+22))\n")
            seen = client.read_until(b"hello-42", WAIT_SECONDS)
            expect(b"hello-42" in seen, "the shell's answer never came back")
        finally:
            client.close()


def check_a_resize_message_changes_the_window_size_of_the_shell():
    with helper() as one:
        client = open_console(one, make_vm(one))
        try:
            client.send_binary(b"stty size\n")
            client.read_until(b"24 80", WAIT_SECONDS)
            client.send_text('{"resize":[100,30]}')
            time.sleep(0.3)
            client.send_binary(b"echo size=$(stty size)\n")
            client.read_until(b"size=30 100", WAIT_SECONDS)
        finally:
            client.close()


def check_closing_the_socket_kills_the_shell_and_frees_the_workload_for_a_new_console():
    with helper() as one:
        vm = make_vm(one)
        first = open_console(one, vm)
        pid = shell_pid(first)
        expect(alive(pid), "the shell is not running while the console is open")
        first.send_close()
        first.wait_for_close()
        first.close()
        expect(wait_gone(pid), f"the shell {pid} is still running after the console closed")
        second = open_console(one, vm)
        deadline = time.time() + 3  # the helper may still be tidying up for a moment after the close
        while not isinstance(second, wsproto.Client) and time.time() < deadline:
            time.sleep(0.2)
            second = open_console(one, vm)
        try:
            expect(isinstance(second, wsproto.Client), f"a second console after the first ended gave {getattr(second, 'status', None)}")
        finally:
            if isinstance(second, wsproto.Client):
                second.close()


def check_dropping_the_connection_without_a_close_frame_also_kills_the_shell():
    with helper() as one:
        client = open_console(one, make_vm(one))
        pid = shell_pid(client)
        client.close()
        expect(wait_gone(pid), f"the shell {pid} survived a dropped connection")


def check_a_second_console_on_the_same_workload_is_refused_with_409():
    with helper() as one:
        vm = make_vm(one)
        first = open_console(one, vm)
        try:
            expect(refused(open_console(one, vm)), "a second console: the upgrade was not refused")
            expect_exact(one, vm, "default", 409, "console_open")
            other = open_console(one, make_vm(one, "vm2"))
            expect(isinstance(other, wsproto.Client), "a console on another workload must work")
            other.close()
        finally:
            first.close()


def check_the_shell_ending_closes_the_socket_normally():
    with helper() as one:
        client = open_console(one, make_vm(one))
        try:
            client.send_binary(b"exit\n")
            code, reason = client.wait_for_close()
            expect(code == 1000 and reason, f"close was {code} {reason!r}; wanted 1000 with a short reason")
        finally:
            client.close()


def check_bad_frames_close_with_1008_and_kill_the_shell():
    cases = {"oversized binary": lambda c: c.send_binary(b"a" * (MAX_FRAME + 1)), "not json": lambda c: c.send_text("hello"),
             "unknown message": lambda c: c.send_text('{"ping":1}'), "zero columns": lambda c: c.send_text('{"resize":[0,24]}'),
             "too many columns": lambda c: c.send_text('{"resize":[501,24]}'), "too many rows": lambda c: c.send_text('{"resize":[80,301]}'),
             "text instead of numbers": lambda c: c.send_text('{"resize":["80","24"]}'), "extra key": lambda c: c.send_text('{"resize":[80,24],"x":1}')}
    with helper() as one:
        for label, misbehave in cases.items():
            client = open_console(one, make_vm(one, "vm-" + label.replace(" ", "-")))
            try:
                pid = shell_pid(client)
                misbehave(client)
                code, _ = client.wait_for_close()
                expect(code == 1008, f"{label}: close code {code}, wanted 1008")
                expect(wait_gone(pid), f"{label}: the shell survived the violation")
            finally:
                client.close()


def check_a_frame_of_exactly_the_limit_and_the_biggest_resize_are_accepted():
    with helper() as one:
        client = open_console(one, make_vm(one))
        try:
            client.send_binary(b":\n" * (MAX_FRAME // 2))  # a full frame of short lines; a pty cannot take 64 KiB without a newline
            client.send_text('{"resize":[500,300]}')
            client.send_binary(b"echo still=$((1+1))\n")
            client.read_until(b"still=2", WAIT_SECONDS)
        finally:
            client.close()


def check_stopping_the_workload_ends_the_console_and_kills_the_shell():
    with helper() as one:
        vm = make_vm(one)
        client = open_console(one, vm)
        try:
            pid = shell_pid(client)
            expect(one.call("POST", f"/v1/workloads/{vm}/stop")[0] == 202, "stop was not accepted")
            code, reason = client.wait_for_close(15)
            expect(code in (1000, 1011) and reason, f"close after stop: {code} {reason!r}")
            expect(wait_gone(pid), "the shell survived the workload stopping")
        finally:
            client.close()


CHECKS = [
    check_the_console_needs_the_command_token_and_a_real_running_workload, check_you_can_type_into_the_shell_and_read_the_answer,
    check_a_resize_message_changes_the_window_size_of_the_shell, check_closing_the_socket_kills_the_shell_and_frees_the_workload_for_a_new_console,
    check_dropping_the_connection_without_a_close_frame_also_kills_the_shell, check_a_second_console_on_the_same_workload_is_refused_with_409,
    check_the_shell_ending_closes_the_socket_normally, check_bad_frames_close_with_1008_and_kill_the_shell,
    check_a_frame_of_exactly_the_limit_and_the_biggest_resize_are_accepted, check_stopping_the_workload_ends_the_console_and_kills_the_shell,
]
