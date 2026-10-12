"""A real OpenSSH server for the checks: runs as the current user on 127.0.0.1 with its own host key and its own authorized keys, no root needed.
Without `answer` it is this computer (a login runs the real command). With `answer` it replays that text to every login, whatever command is sent, which makes a
convincing pretend machine (a Linux box, or a hostile one)."""
import os
import shutil
import socket
import subprocess
import tempfile
import time

SSHD = "/usr/sbin/sshd"


def available():
    return os.path.exists(SSHD) and shutil.which("ssh-keygen") is not None


def _free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class SshServer:
    def __init__(self, answer=None):
        self.dir = tempfile.mkdtemp(prefix="ms-sshd-")
        self.port = _free_port()
        self.process = None
        self.answer = answer
        self.authorized = os.path.join(self.dir, "authorized_keys")
        open(self.authorized, "w").close()
        os.chmod(self.authorized, 0o600)
        self._make_host_key()
        self._write_config()

    def _make_host_key(self):
        for name in ("host_ed25519", "host_ed25519.pub"):
            path = os.path.join(self.dir, name)
            if os.path.exists(path):
                os.remove(path)
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", os.path.join(self.dir, "host_ed25519")], check=True)

    def _write_config(self):
        lines = [f"Port {self.port}", "ListenAddress 127.0.0.1", f"HostKey {self.dir}/host_ed25519", f"AuthorizedKeysFile {self.authorized}",
                 "PasswordAuthentication no", "KbdInteractiveAuthentication no", "PubkeyAuthentication yes", "UsePAM no", "StrictModes no",
                 f"PidFile {self.dir}/sshd.pid", "LogLevel ERROR"]
        if self.answer is not None:
            with open(os.path.join(self.dir, "answer.txt"), "w") as file:
                file.write(self.answer)
            lines.append(f"ForceCommand cat {self.dir}/answer.txt")
        path = os.path.join(self.dir, "sshd_config")
        self._write(path, lines)
        # OpenSSH 9.8+ ignores an address after failed logins. The checks must not depend on that, so it is switched off where the server knows the setting.
        self._write(path, lines + ["PerSourcePenalties no"])
        if subprocess.run([SSHD, "-t", "-f", path], capture_output=True).returncode != 0:
            self._write(path, lines)

    @staticmethod
    def _write(path, lines):
        with open(path, "w") as file:
            file.write("\n".join(lines) + "\n")

    def start(self):
        self.process = subprocess.Popen([SSHD, "-D", "-e", "-f", os.path.join(self.dir, "sshd_config")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            with socket.socket() as probe:
                probe.settimeout(0.2)
                if probe.connect_ex(("127.0.0.1", self.port)) == 0:
                    return self
            time.sleep(0.05)
        raise RuntimeError("the test sshd did not start")

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def authorize(self, public_key_line):
        with open(self.authorized, "a") as file:
            file.write(public_key_line.strip() + "\n")

    def fingerprint(self):
        out = subprocess.run(["ssh-keygen", "-lf", os.path.join(self.dir, "host_ed25519.pub")], capture_output=True, text=True, check=True).stdout
        return out.split()[1]

    def rotate_host_key(self):
        """A different computer (or a man in the middle) answering on the same address: a new host key."""
        old = self.process
        old.terminate()
        old.wait(timeout=5)
        self._make_host_key()
        return self.start()
