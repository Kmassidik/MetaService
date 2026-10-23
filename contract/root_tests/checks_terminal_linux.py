"""The console on helpers of different systems, against a real Root and a fake helper (agent/fake) that serves a /bin/sh console: a Linux machine whose helper says
`terminal` opens one end to end; a Linux machine whose helper does not say it is told to update; an old Mac helper (no flag) still works; and the security rules
(hostile Origin, a ticket that works once, one console per workload) hold for the Linux machine too. The Mac helper itself is checked in checks_terminal.py."""
import secrets
from contextlib import contextmanager

from agent.fake.engine import MachineSpec
from contract import wsproto
from contract.root_tests.checks_gpu import GpuHelper, tell_the_parent
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.checks_terminal import HOSTILE_ORIGIN, REFUSED_UPGRADE, WAIT_SECONDS, error_code, expect_refused, open_socket
from contract.root_tests.support import Browser, expect, running

MACHINE = "linux-box"
UPDATE_MESSAGE = "Update the helper on this machine to use the terminal."
LINUX_WITH_FLAG = MachineSpec(os="linux", arch="x86_64", vm=False, container=True, terminal=True)
LINUX_WITHOUT_FLAG = MachineSpec(os="linux", arch="x86_64", vm=False, container=True, terminal=False)
OLD_MAC = MachineSpec(os="macos", arch="arm64", vm=True, container=False, terminal=False)


def ticket_path(workload):
    return f"/api/machines/{MACHINE}/workloads/{workload}/terminal"


@contextmanager
def machine_with_workload(machine_spec, kind):
    """A Root with one machine that runs a fake helper with one running workload. Yields (root, operator, workload id)."""
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, machine_spec)
        try:
            workload = helper.make("shell-box", kind=kind, gpu_mode="none")
            tell_the_parent(root, machine_token, helper)
            yield root, operator, workload
        finally:
            helper.stop()


def get_ticket(operator, workload):
    reply = operator.write("POST", ticket_path(workload))
    expect(reply.status == 200, f"ticket gave {reply.status}: {reply.raw[:200]!r}")
    return reply.body["ticket"]


def echo_through_the_root(root, operator, workload):
    marker = "marker" + secrets.token_hex(6)
    client = open_socket(root, operator, get_ticket(operator, workload))
    expect(isinstance(client, wsproto.Client), f"the upgrade was refused with {getattr(client, 'status', None)}")
    try:
        client.send_binary(f"echo hel\"\"lo-{marker}\n".encode())
        client.read_until(f"hello-{marker}".encode(), WAIT_SECONDS)
    finally:
        client.close()


def check_a_linux_machine_whose_helper_says_terminal_opens_a_console_end_to_end():
    with machine_with_workload(LINUX_WITH_FLAG, "container") as (root, operator, workload):
        capabilities = operator.request("GET", f"/api/machines/{MACHINE}").body["capabilities"]
        expect(capabilities.get("terminal") is True, f"the machine does not show the terminal flag: {capabilities}")
        echo_through_the_root(root, operator, workload)


def check_a_linux_machine_without_the_flag_is_told_to_update_the_helper():
    with machine_with_workload(LINUX_WITHOUT_FLAG, "container") as (root, operator, workload):
        capabilities = operator.request("GET", f"/api/machines/{MACHINE}").body["capabilities"]
        expect(not capabilities.get("terminal"), f"an old helper shows the terminal flag: {capabilities}")
        refused = operator.write("POST", ticket_path(workload))
        expect(refused.status == 409 and error_code(refused) == "not_supported", f"a Linux machine without the flag: {refused.status} {refused.raw[:160]!r}")
        expect(refused.body["error"]["message"] == UPDATE_MESSAGE, f"the plain message: {refused.body['error']['message']!r}")


def check_an_old_mac_helper_without_the_flag_still_opens_a_console():
    with machine_with_workload(OLD_MAC, "vm") as (root, operator, workload):
        echo_through_the_root(root, operator, workload)


def check_the_terminal_security_rules_hold_for_a_linux_machine():
    with machine_with_workload(LINUX_WITH_FLAG, "container") as (root, operator, workload):
        expect(Browser(root, auto_login=False).request("POST", ticket_path(workload)).status == 401, "a ticket without a session")
        expect(operator.write("POST", ticket_path(workload), origin=HOSTILE_ORIGIN).status == 403, "a ticket from a hostile Origin")
        ticket = get_ticket(operator, workload)
        expect_refused(open_socket(root, operator, ticket, origin=HOSTILE_ORIGIN), REFUSED_UPGRADE, "hostile Origin")
        expect_refused(open_socket(root, operator, ticket, cookies=False), REFUSED_UPGRADE, "no session cookie")
        client = open_socket(root, operator, ticket)
        expect(isinstance(client, wsproto.Client), "the real upgrade was refused")
        try:
            second = operator.write("POST", ticket_path(workload))
            expect(second.status == 409 and error_code(second) == "console_open", f"a second console on one workload: {second.status} {second.raw[:120]!r}")
            client.send_binary(b"a" * 65537)
            code, _ = client.wait_for_close()
            expect(code == 1008, f"an oversized frame closed with {code}, wanted 1008")
        finally:
            client.close()
        expect_refused(open_socket(root, operator, ticket), REFUSED_UPGRADE, "a ticket used a second time")


CHECKS = [
    check_a_linux_machine_whose_helper_says_terminal_opens_a_console_end_to_end, check_a_linux_machine_without_the_flag_is_told_to_update_the_helper,
    check_an_old_mac_helper_without_the_flag_still_opens_a_console, check_the_terminal_security_rules_hold_for_a_linux_machine,
]
