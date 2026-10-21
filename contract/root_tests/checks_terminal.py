"""The console (web terminal): the ticket route, the WebSocket upgrade, a full session, the limits and the audit trail.
A real Root, a real OpenSSH server on loopback and a real helper (simulated engine, which runs /bin/sh in a pty). The Root reaches the helper through its SSH tunnel.
Frames and rules: docs/console-contract.md."""
import json
import secrets
import time
from contextlib import contextmanager

from contract import wsproto
from contract.agent_tests.checks_terminal import alive, shell_pid, wait_gone
from contract.root_tests.checks_remote import authorize_parent, remote
from contract.root_tests.checks_remote_install import add_body, box_folder, start_install, wait_command, wait_for_job, wait_for_tunnel
from contract.root_tests.support import Browser, expect

MACHINE = "test-box"
HOSTILE_ORIGIN = "http://evil.example"
TICKET_SECONDS = 30
TICKET_MIN_CHARS = 32
MAX_CONSOLES = 4
MAX_FRAME = 65536
TICKET_SLOT_TEXT = "console_open"
WAIT_SECONDS = 15
# A refused upgrade is any non-101 HTTP answer (the library gives a bare 400); what matters is that no socket opens. Exact statuses are checked on the ticket route.
REFUSED_UPGRADE = tuple(range(200, 600))


def ticket_path(vm):
    return f"/api/machines/{MACHINE}/workloads/{vm}/terminal"


def make_vm(operator, name):
    reply = operator.write("POST", "/api/workloads", {"name": name, "kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1, "machine": MACHINE})
    expect(reply.status == 202, f"create {name}: {reply.status} {reply.raw[:200]!r}")
    command = wait_command(operator, reply.body["command"]["id"], "succeeded")
    vm = command.get("workloadId") or (command.get("result") or {}).get("workload_id")
    expect(vm, f"no workload id in {command}")
    return vm


def wait_until_listed(operator, vm, state="running", seconds=40):
    deadline = time.time() + seconds
    while time.time() < deadline:
        listed = {w["id"]: w for w in operator.request("GET", f"/api/machines/{MACHINE}").body.get("workloads", [])}
        if vm in listed and listed[vm]["state"] == state:
            return
        time.sleep(0.5)
    raise AssertionError(f"the parent never listed {vm} as {state}")


@contextmanager
def console_world(vm_count=1):
    """A Root with one installed helper machine and `vm_count` running VMs. Yields (root, operator, [vm ids])."""
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        job = wait_for_job(operator, start_install(operator, add_body(server, box_folder())).body["id"])
        expect(job["state"] == "done", f"install: {job.get('error')} {job['steps']}")
        wait_for_tunnel(operator, "connected")
        vms = [make_vm(operator, f"vm{index}") for index in range(vm_count)]
        for vm in vms:
            wait_until_listed(operator, vm)
        yield root, operator, vms


def get_ticket(operator, vm):
    reply = operator.write("POST", ticket_path(vm))
    expect(reply.status == 200, f"ticket gave {reply.status}: {reply.raw[:200]!r}")
    return reply.body["ticket"]


def open_socket(root, operator, ticket, origin="default", cookies=True):
    headers = {"Host": f"localhost:{root.port}", "Origin": root.base if origin == "default" else origin}
    if origin is None:
        del headers["Origin"]
    if cookies and operator.cookies:
        headers["Cookie"] = "; ".join(f"{k}={v}" for k, v in operator.cookies.items())
    return wsproto.Client.connect(root.port, f"/api/terminal/{ticket}", headers)


def connect(root, operator, vm):
    client = open_socket(root, operator, get_ticket(operator, vm))
    expect(isinstance(client, wsproto.Client), f"upgrade refused with {getattr(client, 'status', None)} {getattr(client, 'raw', b'')[:120]!r}")
    return client


def audit_entries(operator, action):
    return [e for e in operator.request("GET", "/api/audit?limit=200").body["entries"] if e["action"] == action]


def wait_for_audit(operator, action, count=1, seconds=WAIT_SECONDS):
    deadline = time.time() + seconds
    while time.time() < deadline:
        found = audit_entries(operator, action)
        if len(found) >= count:
            return found
        time.sleep(0.3)
    raise AssertionError(f"no {count} {action} audit entries; got {audit_entries(operator, action)}")


def expect_refused(reply, statuses, label):
    got = getattr(reply, "status", "opened")
    expect(isinstance(reply, wsproto.Refusal) and reply.status in statuses, f"{label}: wanted {statuses}, got {got}")


def error_code(reply):
    return (reply.body or {}).get("error", {}).get("code")


def check_the_ticket_route_gives_a_ticket_and_refuses_what_it_should():
    with console_world() as (root, operator, (vm,)):
        reply = operator.write("POST", ticket_path(vm))
        expect(reply.status == 200 and set(reply.body) == {"ticket", "expires_in"}, f"shape: {reply.status} {reply.body}")
        ticket = reply.body["ticket"]
        expect(isinstance(ticket, str) and len(ticket) >= TICKET_MIN_CHARS and reply.body["expires_in"] == TICKET_SECONDS, f"ticket: {reply.body}")
        expect(Browser(root, auto_login=False).request("POST", ticket_path(vm)).status == 401, "a ticket without a session")
        expect(operator.request("POST", ticket_path(vm), headers={}).status == 403, "a ticket without the CSRF token")
        expect(operator.write("POST", ticket_path(vm), origin=HOSTILE_ORIGIN).status == 403, "a ticket from a hostile Origin")
        for label, path, code in (("no such machine", f"/api/machines/nope/workloads/{vm}/terminal", "not_found"), ("no such VM", ticket_path("no-such-vm"), "not_found")):
            gone = operator.write("POST", path)
            expect(gone.status == 404 and error_code(gone) == code, f"{label}: {gone.status} {gone.raw[:120]!r}")
        stopped = make_vm(operator, "stopme")
        expect(operator.write("POST", f"/api/machines/{MACHINE}/workloads/{stopped}/stop").status == 202, "stop")
        wait_until_listed(operator, stopped, "stopped")
        refused = operator.write("POST", ticket_path(stopped))
        expect(refused.status == 409 and error_code(refused) == "not_running", f"a stopped VM: {refused.status} {refused.raw[:120]!r}")


def check_the_upgrade_needs_session_origin_and_a_good_ticket_and_a_ticket_works_once():
    with console_world() as (root, operator, (vm,)):
        ticket = get_ticket(operator, vm)
        expect_refused(open_socket(root, operator, ticket, cookies=False), REFUSED_UPGRADE, "no session cookie")
        expect_refused(open_socket(root, operator, ticket, origin=HOSTILE_ORIGIN), REFUSED_UPGRADE, "hostile Origin")
        expect_refused(open_socket(root, operator, ticket, origin=root.base + ".evil.com"), REFUSED_UPGRADE, "look-alike Origin")
        expect_refused(open_socket(root, operator, ticket, origin="null"), REFUSED_UPGRADE, "null Origin")
        expect_refused(open_socket(root, operator, secrets.token_urlsafe(32)), REFUSED_UPGRADE, "a ticket nobody made")
        expect_refused(open_socket(root, operator, "x" * 8), REFUSED_UPGRADE, "a short ticket")
        expect(not audit_entries(operator, "console_open"), "a refused upgrade opened a console")
        first = open_socket(root, operator, ticket)  # the refusals above must not have used up the ticket
        expect(isinstance(first, wsproto.Client), f"the real upgrade was refused: {getattr(first, 'status', None)}")
        first.close()
        wait_for_audit(operator, "console_close")
        expect_refused(open_socket(root, operator, ticket), REFUSED_UPGRADE, "a ticket used a second time")


def check_a_ticket_reserves_the_slot_until_the_console_closes_or_the_ticket_expires():
    with console_world(vm_count=2) as (root, operator, (vm, other)):
        ticket = get_ticket(operator, vm)
        second = operator.write("POST", ticket_path(vm))
        expect(second.status == 409 and error_code(second) == TICKET_SLOT_TEXT, f"a second ticket while the first is unused: {second.status} {second.raw[:120]!r}")
        expect(operator.write("POST", ticket_path(other)).status == 200, "a ticket for another VM must not be blocked")
        client = open_socket(root, operator, ticket)
        expect(isinstance(client, wsproto.Client), "the first ticket did not open")
        try:
            expect(operator.write("POST", ticket_path(vm)).status == 409, "a ticket while the console is open")
        finally:
            client.close()
        wait_for_audit(operator, "console_close")
        expect(operator.write("POST", ticket_path(vm)).status == 200, "the slot was not freed when the console closed")
        time.sleep(TICKET_SECONDS + 1)
        again = operator.write("POST", ticket_path(vm))
        expect(again.status == 200, f"the slot was not freed when the unused ticket expired: {again.status} {again.raw[:120]!r}")


def check_an_old_ticket_is_refused():
    with console_world() as (root, operator, (vm,)):
        ticket = get_ticket(operator, vm)
        time.sleep(TICKET_SECONDS + 1)
        expect_refused(open_socket(root, operator, ticket), REFUSED_UPGRADE, "a ticket older than its 30 seconds")


def check_a_session_types_resizes_and_closing_it_kills_the_shell_and_the_audit_has_no_content():
    marker = "marker" + secrets.token_hex(6)
    with console_world() as (root, operator, (vm,)):
        client = connect(root, operator, vm)
        try:
            pid = shell_pid(client)
            client.send_binary(f"echo hel\"\"lo-{marker}\n".encode())
            client.read_until(f"hello-{marker}".encode(), WAIT_SECONDS)
            client.send_text('{"resize":[100,30]}')
            time.sleep(0.3)
            client.send_binary(b"echo size=$(stty size)\n")
            client.read_until(b"size=30 100", WAIT_SECONDS)
            expect(alive(pid), "the shell is not running during the session")
            client.send_close()
            client.wait_for_close()
        finally:
            client.close()
        expect(wait_gone(pid), f"the shell {pid} is still running after Close")
        opened, closed = wait_for_audit(operator, "console_open")[0], wait_for_audit(operator, "console_close")[0]
        for entry in (opened, closed):
            text = json.dumps(entry)
            expect(MACHINE in text and vm in text and entry["actor"] in text, f"the audit entry lacks machine, VM or operator: {entry}")
        expect("seconds" in json.dumps(closed), f"the close entry has no seconds: {closed}")
        everything = json.dumps(operator.request("GET", "/api/audit?limit=200").body)
        expect(marker not in everything and "hello" not in everything, "typed or printed content reached the audit log")


def check_bad_frames_close_the_socket_with_1008_through_the_parent():
    cases = {"oversized binary": lambda c: c.send_binary(b"a" * (MAX_FRAME + 1)), "not json": lambda c: c.send_text("hello"),
             "zero columns": lambda c: c.send_text('{"resize":[0,24]}'), "too many columns": lambda c: c.send_text('{"resize":[501,24]}'),
             "too many rows": lambda c: c.send_text('{"resize":[80,301]}'), "unknown message": lambda c: c.send_text('{"ping":1}')}
    with console_world(vm_count=1) as (root, operator, (vm,)):
        for label, misbehave in cases.items():
            client = connect(root, operator, vm)
            try:
                pid = shell_pid(client)
                misbehave(client)
                code, _ = client.wait_for_close()
                expect(code == 1008, f"{label}: close code {code}, wanted 1008")
                expect(wait_gone(pid), f"{label}: the shell survived")
            finally:
                client.close()
            wait_for_audit(operator, "console_close", count=list(cases).index(label) + 1)


def check_one_console_per_vm_and_four_in_total():
    with console_world(vm_count=MAX_CONSOLES + 1) as (root, operator, vms):
        clients = []
        try:
            first = connect(root, operator, vms[0])
            clients.append(first)
            again = operator.write("POST", ticket_path(vms[0]))
            expect(again.status == 409 and error_code(again) == "console_open", f"a second console on one VM: {again.status} {again.raw[:120]!r}")
            for vm in vms[1:MAX_CONSOLES]:
                clients.append(connect(root, operator, vm))
            fifth = operator.write("POST", ticket_path(vms[MAX_CONSOLES]))
            expect(fifth.status == 429 and error_code(fifth) == "too_many_consoles", f"the fifth console: {fifth.status} {fifth.raw[:120]!r}")
            clients.pop().close()
            wait_for_audit(operator, "console_close")
            expect(operator.write("POST", ticket_path(vms[MAX_CONSOLES])).status == 200, "a console slot was not freed when one closed")
        finally:
            for client in clients:
                client.close()


def check_stopping_the_vm_from_the_panel_ends_the_console_with_a_reason_and_kills_the_shell():
    with console_world() as (root, operator, (vm,)):
        client = connect(root, operator, vm)
        try:
            pid = shell_pid(client)
            expect(operator.write("POST", f"/api/machines/{MACHINE}/workloads/{vm}/stop").status == 202, "stop")
            code, reason = client.wait_for_close(WAIT_SECONDS)
            expect(code == 1000 and reason, f"close after stop: {code} {reason!r}")
            expect(wait_gone(pid), "the shell survived the VM being stopped")
        finally:
            client.close()
        wait_for_audit(operator, "console_close")


def check_the_shell_ending_closes_the_console_normally():
    with console_world() as (root, operator, (vm,)):
        client = connect(root, operator, vm)
        try:
            client.send_binary(b"exit\n")
            code, reason = client.wait_for_close(WAIT_SECONDS)
            expect(code == 1000 and reason, f"close after exit: {code} {reason!r}")
        finally:
            client.close()
        wait_for_audit(operator, "console_close")


CHECKS = [
    check_the_ticket_route_gives_a_ticket_and_refuses_what_it_should, check_the_upgrade_needs_session_origin_and_a_good_ticket_and_a_ticket_works_once,
    check_a_ticket_reserves_the_slot_until_the_console_closes_or_the_ticket_expires, check_an_old_ticket_is_refused, check_a_session_types_resizes_and_closing_it_kills_the_shell_and_the_audit_has_no_content,
    check_bad_frames_close_the_socket_with_1008_through_the_parent, check_one_console_per_vm_and_four_in_total,
    check_stopping_the_vm_from_the_panel_ends_the_console_with_a_reason_and_kills_the_shell, check_the_shell_ending_closes_the_console_normally,
]
