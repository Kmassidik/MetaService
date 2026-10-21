"""Install it for me: a missing part is installed over SSH with the person's sudo password, then the computer is checked again. The other computer is a pretend Debian
(fakes/fake_linux.py) behind a real OpenSSH server on loopback: its sudo, apt-get and incus are stubs, so no real package or password is ever involved.
The password is a recognizable fake. Every place that could keep it is searched for it."""
import pathlib
import tempfile
from contextlib import contextmanager

from contract.agent_tests.support import MACOS_BINARY
from contract.root_tests.checks_remote import authorize_parent, rows, verify_body
from contract.root_tests.checks_scan import Skip
from contract.root_tests.fakes.fake_linux import FakeLinux, PASSWORD
from contract.root_tests.fakes.loopback_ssh import available
from contract.root_tests.support import Browser, RunningRoot, expect

FIX = "/api/remote/fix"


@contextmanager
def fake_computer(password=PASSWORD):
    if not available():
        raise Skip("no OpenSSH server program on this machine")
    server = FakeLinux(password).start()
    extra = ["--ui-dir", tempfile.mkdtemp(prefix="ms-no-ui-"), "--agent-binary", str(MACOS_BINARY), "--remote-engine", "simulated", "--remote-allow-loopback", "yes"]
    root = RunningRoot(extra_args=extra).start()
    try:
        operator = Browser(root)
        authorize_parent(operator, server)
        yield root, operator, server
    finally:
        root.stop()
        server.stop()


def fix_body(server, part="vm_tool", password=PASSWORD, **more):
    return {**verify_body(server), "fix": part, "sudo_password": password, **more}


def leaks(secret, root, operator, server, replies):
    """Every place the password must never be: answers, the audit log, the Root's output and files, and what the other computer's programs saw as arguments or environment."""
    found = []
    if any(secret in reply.raw.decode() for reply in replies):
        found.append("an answer")
    if secret in operator.request("GET", "/api/audit").raw.decode():
        found.append("the audit log")
    if secret in server.commands() + server.environment_seen_by_sudo():
        found.append("the other computer's arguments or environment")
    root.stop()
    found += [f"file {path}" for path in pathlib.Path(root.dir).rglob("*") if path.is_file() and secret.encode() in path.read_bytes()]
    if secret in (root.process.stderr.read().decode() + root.process.stdout.read().decode()):
        found.append("the Root's output")
    return found


def check_a_missing_part_shows_an_install_offer_only_where_it_can_be_done():
    with fake_computer() as (root, operator, server):
        table = rows(operator.write("POST", "/api/remote/verify", verify_body(server)))
        expect(table["vm_tool"]["install"] == {"part": "vm_tool", "needs_password": True} and table["python"]["install"] == {"part": "python", "needs_password": True}, f"offers: {table['vm_tool']}")
        expect("sudo apt install incus" in table["vm_tool"]["fix"], "the manual line stays next to the button")
        expect("install" not in table["memory"] and "install" not in table["login"], "an offer only where there is something to install")
    with fake_computer() as (root, operator, server):
        server.state("passwordless")
        server._file("answer.txt", open(f"{server.dir}/answer.txt").read().replace("sudo=password", "sudo=passwordless"))
        expect(rows(operator.write("POST", "/api/remote/verify", verify_body(server)))["vm_tool"]["install"]["needs_password"] is False, "no password needed when sudo asks for none")
    with fake_computer() as (root, operator, server):
        server._file("answer.txt", open(f"{server.dir}/answer.txt").read().replace("pkg=apt", "pkg=dnf"))
        table = rows(operator.write("POST", "/api/remote/verify", verify_body(server)))
        expect("install" not in table["vm_tool"] and "sudo dnf install incus" in table["vm_tool"]["fix"], f"dnf: manual line only: {table['vm_tool']}")


def check_install_it_for_me_installs_sets_up_adds_the_group_and_checks_again():
    with fake_computer() as (root, operator, server):
        reply = operator.write("POST", FIX, fix_body(server))
        expect(reply.status == 200, f"fix: {reply.status} {reply.raw[:300]!r}")
        table = rows(reply)
        expect(table["vm_tool"]["ok"] is True and "install" not in table["vm_tool"] and table["python"]["ok"] is False, f"Incus is a tick now, Python still a cross: {table['vm_tool']}")
        log = server.commands()
        for part in ["install incus", "incus admin init --minimal", "usermod -a -G incus-admin build", "sudo mode=S"]:
            expect(part in log, f"{part!r} was not run: {log[-600:]}")
        expect(log.index("update") < log.index("install incus") < log.index("admin init"), "update, install, then set up")
        second = operator.write("POST", FIX, fix_body(server, part="python"))
        expect(second.status == 200 and rows(second)["python"]["ok"] is True, f"python: {second.status} {second.raw[:200]!r}")
        expect(log.count("admin init") == 1 and server.commands().count("admin init") == 1, "Incus is set up once")
        expect("remote.fix" in [entry["action"] for entry in operator.request("GET", "/api/audit").body["entries"]], "the install is in the audit log")


def check_an_incus_that_is_already_set_up_is_not_set_up_again():
    with fake_computer() as (root, operator, server):
        server.state("initialised")
        expect(operator.write("POST", FIX, fix_body(server)).status == 200, "fix")
        expect("admin init" not in server.commands(), "init must run only when the server is not set up")


def check_a_login_that_needs_no_sudo_password_installs_without_one():
    with fake_computer() as (root, operator, server):
        server.state("passwordless")
        server._file("answer.txt", open(f"{server.dir}/answer.txt").read().replace("sudo=password", "sudo=passwordless"))
        body = fix_body(server)
        del body["sudo_password"]
        reply = operator.write("POST", FIX, body)
        expect(reply.status == 200 and rows(reply)["vm_tool"]["ok"] is True, f"passwordless: {reply.status} {reply.raw[:200]!r}")
        expect("sudo mode=n" in server.commands(), "no password: sudo -n")


def check_the_sudo_password_is_never_in_arguments_environment_files_logs_answers_or_the_audit_log():
    with fake_computer() as (root, operator, server):
        replies = [operator.write("POST", FIX, fix_body(server)), operator.write("POST", FIX, fix_body(server, part="python"))]
        expect([reply.status for reply in replies] == [200, 200], f"fix: {[reply.raw[:100] for reply in replies]}")
        found = leaks(PASSWORD, root, operator, server, replies)
        expect(not found, f"the sudo password leaked into: {found}")


def check_a_wrong_password_a_non_sudoer_and_a_missing_password_are_said_plainly_and_install_nothing():
    wrong = "Wrong-Pw-" + "5d2b8f"
    with fake_computer() as (root, operator, server):
        reply = operator.write("POST", FIX, fix_body(server, password=wrong))
        expect(reply.status == 422 and reply.body["error"]["code"] == "remote_sudo_refused" and "password" in reply.body["error"]["message"], f"wrong password: {reply.status} {reply.raw[:200]!r}")
        expect(not server.has("incus") and "apt-get" not in server.commands(), "nothing may be installed after a wrong password")
        found = leaks(wrong, root, operator, server, [reply])
        expect(not found, f"the wrong password leaked into: {found}")
    with fake_computer() as (root, operator, server):
        server.state("sudo_denied")
        reply = operator.write("POST", FIX, fix_body(server))
        expect(reply.status == 422 and "not allowed to use sudo" in reply.body["error"]["message"], f"not a sudoer: {reply.status} {reply.raw[:200]!r}")
    with fake_computer() as (root, operator, server):
        body = fix_body(server)
        del body["sudo_password"]
        reply = operator.write("POST", FIX, body)
        expect(reply.status == 422 and "asks for a password" in reply.body["error"]["message"], f"no password given: {reply.status} {reply.raw[:200]!r}")


def check_a_busy_apt_no_network_and_a_system_without_the_package_fail_with_their_own_words_and_leave_nothing():
    cases = [("apt_lock", "another program is using the package manager"), ("no_network", "could not reach the internet"), ("no_candidate", "no Incus package")]
    for state, words in cases:
        with fake_computer() as (root, operator, server):
            server.state(state)
            reply = operator.write("POST", FIX, fix_body(server))
            expect(reply.status == 502 and reply.body["error"]["code"] == "remote_install_failed" and words in reply.body["error"]["message"], f"{state}: {reply.status} {reply.raw[:300]!r}")
            expect(not server.has("incus") and "usermod" not in server.commands(), f"{state}: a failed install must not go on to set things up")
            expect(PASSWORD not in reply.raw.decode(), f"{state}: the password is in the answer")


def check_install_it_for_me_has_the_same_guards_and_refuses_what_it_cannot_do():
    with fake_computer() as (root, operator, server):
        expect(Browser(root, auto_login=False).request("POST", FIX, fix_body(server)).status == 401, "without a login")
        expect(operator.request("POST", FIX, fix_body(server), origin="https://evil.example").status in (401, 403), "from another origin")
        for label, body in [("unknown part", fix_body(server, part="rm -rf /")), ("extra field", fix_body(server, extra=1)), ("password and key", {**fix_body(server), "password": "x"})]:
            expect(operator.write("POST", FIX, body).status == 400, label)
    with fake_computer() as (root, operator, server):
        server._file("answer.txt", open(f"{server.dir}/answer.txt").read().replace("pkg=apt\n", ""))
        reply = operator.write("POST", FIX, fix_body(server))
        expect(reply.status == 409 and reply.body["error"]["code"] == "remote_fix_unavailable", f"not apt: {reply.status} {reply.raw[:200]!r}")
        expect("sudo" not in server.commands(), "nothing may be run where the install is not offered")


def check_a_windows_computer_is_one_plain_cross_and_nothing_crashes():
    with fake_computer() as (root, operator, server):
        server.state("windows")
        reply = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(reply.status == 200 and reply.body["can_add"] is False and reply.body["system"] == "Windows", f"windows: {reply.status} {reply.raw[:300]!r}")
        table = rows(reply)
        expect(list(table) == ["login", "system"] and table["system"]["ok"] is False and "Windows is not supported yet" in table["system"]["detail"] and table["system"]["fix"], f"rows: {table}")
        expect("install" not in table["system"], "no install is offered for Windows")
        fixed = operator.write("POST", FIX, fix_body(server))
        expect(fixed.status == 409 and fixed.body["error"]["code"] == "remote_fix_unavailable", f"fix on windows: {fixed.status} {fixed.raw[:200]!r}")


CHECKS = [check_a_missing_part_shows_an_install_offer_only_where_it_can_be_done, check_install_it_for_me_installs_sets_up_adds_the_group_and_checks_again,
          check_an_incus_that_is_already_set_up_is_not_set_up_again, check_a_login_that_needs_no_sudo_password_installs_without_one,
          check_the_sudo_password_is_never_in_arguments_environment_files_logs_answers_or_the_audit_log,
          check_a_wrong_password_a_non_sudoer_and_a_missing_password_are_said_plainly_and_install_nothing,
          check_a_busy_apt_no_network_and_a_system_without_the_package_fail_with_their_own_words_and_leave_nothing,
          check_install_it_for_me_has_the_same_guards_and_refuses_what_it_cannot_do, check_a_windows_computer_is_one_plain_cross_and_nothing_crashes]
