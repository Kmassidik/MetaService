"""Connect (add another computer, step one and two): host key, login, what the computer is. Against a real OpenSSH server on loopback, no root needed."""
import getpass
import glob
import os
import signal
import pathlib
import socket
import subprocess
import tempfile
import threading
import uuid
from contextlib import contextmanager

from contract.agent_tests.support import MACOS_BINARY
from contract.root_tests.checks_scan import Skip
from contract.root_tests.fakes.loopback_ssh import SshServer, available
from contract.root_tests.support import Browser, RunningRoot, expect

LINUX = "os=Linux\narch=x86_64\nuser=build\nhome=/home/build\nversion=Ubuntu 24.04.1 LTS\nchip=Intel Xeon\ncpu=8\nram_mb=32108\nkvm=yes\ndisk_free_gb=412\ntool=curl\nsudo=none\nport_9101=free\n"
OTHER_FINGERPRINT = "SHA256:" + "A" * 43


BOXES = []


def stop_boxes():
    """Stops the programs a test left running in its boxes (a box that was removed has none), so a test run never leaves processes behind."""
    while BOXES:
        pid_file = BOXES.pop() / "state" / "agent.pid"
        try:
            os.kill(int(pid_file.read_text()), signal.SIGTERM)
        except (OSError, ValueError):
            pass


@contextmanager
def remote(answer=None, allow_loopback=True, agent_binary=MACOS_BINARY):
    if not available():
        raise Skip("no OpenSSH server program on this machine")
    server = SshServer(answer=answer).start()
    extra = ["--ui-dir", tempfile.mkdtemp(prefix="ms-no-ui-"), "--agent-binary", str(agent_binary), "--remote-engine", "simulated"] + (["--remote-allow-loopback", "yes"] if allow_loopback else [])
    root = RunningRoot(extra_args=extra).start()
    try:
        yield root, Browser(root), server
    finally:
        root.stop()
        stop_boxes()
        server.stop()


def target(server, **more):
    return {"host": "127.0.0.1", "port": server.port, **more}


def verify_body(server, fingerprint=None, **more):
    return {**target(server), "user": getpass.getuser(), "use_key": True, "fingerprint": fingerprint or server.fingerprint(), **more}


def authorize_parent(operator, server):
    key = operator.request("GET", "/api/remote/key")
    expect(key.status == 200 and key.body["public_key"].startswith("ssh-ed25519 "), f"parent key: {key.status} {key.raw[:100]!r}")
    server.authorize(key.body["public_key"])
    return key.body["public_key"]


def rows(reply):
    return {row["id"]: row for row in reply.body["requirements"]}


def check_connecting_needs_a_login_and_only_reaches_private_addresses():
    with remote(allow_loopback=False) as (root, operator, server):
        expect(Browser(root, auto_login=False).request("POST", "/api/remote/probe", target(server)).status == 401, "probe without a login")
        expect(Browser(root, auto_login=False).request("GET", "/api/remote/key").status == 401, "key without a login")
        blocked = operator.write("POST", "/api/remote/probe", target(server))
        expect(blocked.status == 400 and blocked.body["error"]["code"] == "remote_not_allowed", f"loopback must be refused by default: {blocked.status} {blocked.raw[:120]!r}")
        public = operator.write("POST", "/api/remote/probe", {"host": "8.8.8.8"})
        expect(public.status == 400 and public.body["error"]["code"] == "remote_not_allowed", f"a public address: {public.status}")


def check_connecting_refuses_hosts_users_and_fields_that_could_become_ssh_options():
    with remote() as (root, operator, server):
        for label, path, body in [("option as host", "/api/remote/probe", {"host": "-oProxyCommand=evil"}), ("space in host", "/api/remote/probe", {"host": "a b"}),
                                  ("extra field", "/api/remote/probe", {"host": "127.0.0.1", "user": "root"}), ("bad port", "/api/remote/probe", {"host": "127.0.0.1", "port": 0}),
                                  ("option as user", "/api/remote/verify", verify_body(server, user="-oProxyCommand=x")),
                                  ("bad fingerprint", "/api/remote/verify", verify_body(server, fingerprint="SHA256:short")),
                                  ("password and key", "/api/remote/verify", verify_body(server, password="x")),
                                  ("neither", "/api/remote/verify", {**verify_body(server), "use_key": False})]:
            reply = operator.write("POST", path, body)
            expect(reply.status == 400, f"{label}: {reply.status} {reply.raw[:120]!r}")
        expect(operator.write("POST", "/api/remote/verify", {**verify_body(server), "user": "a;b"}).status == 400, "user with a semicolon")


def check_the_host_key_fingerprint_shown_is_the_one_ssh_keygen_shows():
    with remote() as (root, operator, server):
        reply = operator.write("POST", "/api/remote/probe", target(server))
        expect(reply.status == 200, f"probe: {reply.status} {reply.raw[:160]!r}")
        expect(reply.body["fingerprint"] == server.fingerprint(), f"fingerprint {reply.body['fingerprint']} != {server.fingerprint()}")
        expect(reply.body["key_type"] == "ssh-ed25519" and reply.body["trusted"] is False and reply.body["address"] == "127.0.0.1", f"probe body: {reply.body}")
        expect(not os.path.exists(os.path.join(root.dir, "ssh", "known_hosts")), "a probe must not trust the key by itself")


def answer_plain(listener, stop):
    """A server that says hello and is not SSH."""
    while not stop.is_set():
        try:
            listener.accept()[0].sendall(b"hello, I am not ssh\r\n")
        except OSError:
            return


def check_nothing_listening_or_not_ssh_is_said_plainly():
    with remote() as (root, operator, server):
        closed = operator.write("POST", "/api/remote/probe", {"host": "127.0.0.1", "port": 1})
        expect(closed.status == 502 and closed.body["error"]["code"] == "remote_no_host_key", f"closed port: {closed.status} {closed.raw[:140]!r}")
        plain = socket.socket()
        plain.bind(("127.0.0.1", 0))
        plain.listen()
        stop = threading.Event()
        threading.Thread(target=lambda: answer_plain(plain, stop), daemon=True).start()
        not_ssh = operator.write("POST", "/api/remote/probe", {"host": "127.0.0.1", "port": plain.getsockname()[1]})
        stop.set()
        plain.close()
        expect(not_ssh.status == 502 and not_ssh.body["error"]["code"] == "remote_no_host_key", f"not ssh: {not_ssh.status} {not_ssh.raw[:140]!r}")


def check_the_parents_own_key_logs_in_and_reads_what_this_computer_is():
    with remote() as (root, operator, server):
        first = authorize_parent(operator, server)
        expect(operator.request("GET", "/api/remote/key").body["public_key"] == first, "the parent's key changed between two reads")
        reply = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(reply.status == 200, f"verify: {reply.status} {reply.raw[:200]!r}")
        facts = reply.body["facts"]
        expect(facts["os"] == "Darwin" and facts["user"] == getpass.getuser() and facts["cpu_cores"] >= 1 and facts["ram_mb"] >= 1024, f"facts: {facts}")
        expect(list(rows(reply)) == ["login", "system", "agent", "memory", "disk", "vm_support", "vm_tool", "python", "admin", "port", "parent"], f"rows: {list(rows(reply))}")
        expect(rows(reply)["login"]["detail"].endswith(server.fingerprint() + "."), "the list must show the host key it trusted")
        expect(rows(reply)["agent"]["ok"] is True, "this Mac has a MetaService program built, so the agent row must pass")
        expect("folder" in reply.body["isolation"] and reply.body["fingerprint"] == server.fingerprint(), f"isolation/fingerprint: {reply.body['isolation']}")
        pinned = pathlib.Path(root.dir, "ssh", "known_hosts").read_text()
        expect(f"[127.0.0.1]:{server.port} ssh-ed25519 " in pinned, f"the confirmed key must be pinned: {pinned!r}")
        again = operator.write("POST", "/api/remote/probe", target(server))
        expect(again.body["trusted"] is True, "after a login the key counts as trusted")
        actions = [entry["action"] for entry in operator.request("GET", "/api/audit").body["entries"]]
        expect("remote.probe" in actions and "remote.verify" in actions, f"audit: {actions[:6]}")


def check_a_pretend_linux_computer_without_our_program_cannot_be_added():
    with remote(answer=LINUX) as (root, operator, server):
        authorize_parent(operator, server)
        reply = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(reply.status == 200, f"verify: {reply.status} {reply.raw[:200]!r}")
        table = rows(reply)
        expect(reply.body["facts"]["os"] == "Linux" and reply.body["system"].startswith("Ubuntu 24.04.1 LTS"), f"system: {reply.body['system']}")
        expect(table["agent"]["ok"] is False and "linux-x86_64" in table["agent"]["detail"], f"agent row: {table['agent']}")
        expect(reply.body["can_add"] is False, "no program for linux-x86_64 on this parent, so it cannot be added")
        expect(table["vm_support"]["ok"] is True and table["vm_tool"]["ok"] is False and table["vm_tool"]["optional"] is True, "kvm yes, Incus missing but optional")
        expect(reply.body["isolation"] == ["folder"], f"no sudo means only the folder box: {reply.body['isolation']}")


def check_a_wrong_fingerprint_is_refused_and_nothing_is_trusted():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        reply = operator.write("POST", "/api/remote/verify", verify_body(server, fingerprint=OTHER_FINGERPRINT))
        expect(reply.status == 409 and reply.body["error"]["code"] == "remote_fingerprint_mismatch", f"mismatch: {reply.status} {reply.raw[:140]!r}")
        expect(not os.path.exists(os.path.join(root.dir, "ssh", "known_hosts")), "a refused key must not be pinned")


def check_a_key_the_computer_does_not_accept_is_a_refused_login():
    with remote() as (root, operator, server):
        reply = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(reply.status == 422 and reply.body["error"]["code"] == "remote_login_refused", f"refused login: {reply.status} {reply.raw[:160]!r}")


def check_a_changed_host_key_is_refused_and_the_trusted_one_is_kept():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        expect(operator.write("POST", "/api/remote/verify", verify_body(server)).status == 200, "first login")
        known = pathlib.Path(root.dir, "ssh", "known_hosts")
        before = known.read_text()
        server.rotate_host_key()
        probe = operator.write("POST", "/api/remote/probe", target(server))
        expect(probe.status == 409 and probe.body["error"]["code"] == "remote_host_key_changed", f"probe after a new key: {probe.status} {probe.raw[:140]!r}")
        verify = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(verify.status == 409 and verify.body["error"]["code"] == "remote_host_key_changed", f"verify after a new key: {verify.status} {verify.raw[:140]!r}")
        expect(known.read_text() == before, "the trusted key must never be replaced")


def check_a_password_is_used_once_and_never_kept_shown_or_logged():
    secret = "S3cret-" + uuid.uuid4().hex
    with remote() as (root, operator, server):
        reply = operator.write("POST", "/api/remote/verify", target(server, user=getpass.getuser(), password=secret, fingerprint=server.fingerprint()))
        expect(reply.status == 422 and reply.body["error"]["code"] == "remote_login_refused", f"password refused by a key-only server: {reply.status} {reply.raw[:160]!r}")
        expect("only accepts keys" in reply.body["error"]["message"], f"a key-only server should be named as such: {reply.body['error']['message']!r}")
        expect(secret not in reply.raw.decode(), "the password came back in the answer")
        expect(secret not in operator.request("GET", "/api/audit").raw.decode(), "the password is in the audit log")
        askpass = pathlib.Path(root.dir, "ssh", "askpass.sh")
        expect(askpass.exists() and secret not in askpass.read_text() and os.access(askpass, os.X_OK) and oct(askpass.stat().st_mode & 0o777) == "0o700", "the askpass helper must hold no password and be private")
        root.stop()
        found = [str(path) for path in pathlib.Path(root.dir).rglob("*") if path.is_file() and secret.encode() in path.read_bytes()]
        expect(not found, f"the password was written to disk: {found}")
        expect(secret not in (root.process.stderr.read().decode() + root.process.stdout.read().decode()), "the password is in the Root's output")


def check_the_parents_private_key_is_never_on_disk_in_clear_and_its_agent_stops_with_the_root():
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        expect(operator.write("POST", "/api/remote/verify", verify_body(server)).status == 200, "login")
        sockets = glob.glob(f"/tmp/ms-ssh-{os.getuid()}-*")
        expect(len(sockets) >= 1, "the private ssh-agent has not started")
        for folder in sockets:
            expect(oct(os.stat(folder).st_mode & 0o777) == "0o700", f"{folder} must be private")
            expect(all(not os.path.isfile(os.path.join(folder, name)) for name in os.listdir(folder)), "only a socket may be in the agent's folder")
        for path in [p for p in pathlib.Path(root.dir).rglob("*") if p.is_file()]:
            expect(b"BEGIN OPENSSH PRIVATE KEY" not in path.read_bytes(), f"a private key in clear is in {path}")
        root.stop()
        left = [folder for folder in glob.glob(f"/tmp/ms-ssh-{os.getuid()}-*") if folder in sockets]
        expect(not left, f"the private agent's folder was left behind: {left}")
        running = subprocess.run(["pgrep", "-f", "ssh-agent -D -a /tmp/ms-ssh-"], capture_output=True, text=True).stdout.split()
        expect(not any(f"-{pid}" in "".join(sockets) for pid in running) and not [p for p in running if open_file_of(p, sockets)], "the private ssh-agent kept running after the Root stopped")


def open_file_of(pid, folders):
    command = subprocess.run(["ps", "-o", "command=", "-p", pid], capture_output=True, text=True).stdout
    return any(folder in command for folder in folders)


def check_repeated_logins_on_one_computer_are_stopped_before_they_look_like_an_attack():
    """Four successful logins in a minute are allowed, the fifth is stopped. (Failed ones would be punished by sshd itself, which these checks must not trigger.)"""
    with remote() as (root, operator, server):
        authorize_parent(operator, server)
        codes = [operator.write("POST", "/api/remote/verify", verify_body(server)).status for _ in range(5)]
        expect(codes[:4] == [200] * 4 and codes[4] == 429, f"four tries then a stop: {codes}")


def check_an_answer_from_the_other_computer_is_cut_down_and_a_useless_one_is_refused():
    hostile = "os=Linux\narch=x86_64\nuser=evil\nversion=" + "A" * 600 + "\nchip=bad\x1b[31mred\x07\ntool=rm\nsudo=root\nram_mb=lots\nport_9101=free\n"
    with remote(answer=hostile) as (root, operator, server):
        authorize_parent(operator, server)
        reply = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(reply.status == 200, f"hostile but readable: {reply.status} {reply.raw[:160]!r}")
        expect(len(reply.body["facts"]["version"]) == 120 and "\x1b" not in reply.raw.decode() and "\x07" not in reply.raw.decode(), "the answer was not cut down to a printable line")
    with remote(answer="nothing useful here\n") as (root, operator, server):
        authorize_parent(operator, server)
        reply = operator.write("POST", "/api/remote/verify", verify_body(server))
        expect(reply.status == 502 and reply.body["error"]["code"] == "remote_no_answer", f"useless answer: {reply.status} {reply.raw[:140]!r}")


CHECKS = [check_connecting_needs_a_login_and_only_reaches_private_addresses, check_connecting_refuses_hosts_users_and_fields_that_could_become_ssh_options,
          check_the_host_key_fingerprint_shown_is_the_one_ssh_keygen_shows, check_nothing_listening_or_not_ssh_is_said_plainly,
          check_the_parents_own_key_logs_in_and_reads_what_this_computer_is, check_a_pretend_linux_computer_without_our_program_cannot_be_added,
          check_a_wrong_fingerprint_is_refused_and_nothing_is_trusted, check_a_key_the_computer_does_not_accept_is_a_refused_login,
          check_a_changed_host_key_is_refused_and_the_trusted_one_is_kept, check_a_password_is_used_once_and_never_kept_shown_or_logged,
          check_the_parents_private_key_is_never_on_disk_in_clear_and_its_agent_stops_with_the_root,
          check_repeated_logins_on_one_computer_are_stopped_before_they_look_like_an_attack, check_an_answer_from_the_other_computer_is_cut_down_and_a_useless_one_is_refused]
