"""A pretend Debian computer behind a real OpenSSH server on loopback, for the "Install it for me" checks. Every login runs a small dispatcher:
the check script gets a canned answer (with the tools that the fake installs showing up), and any other command runs in a shell whose PATH starts with fake
`sudo`, `apt-get`, `apt-cache`, `incus`, `usermod`, `getent`, `id` and `sleep`. The real sudo and apt are never reached: the dispatcher refuses to run if `sudo` is not the fake.
The fakes log what they were called with (their arguments and, for sudo, their environment), so a check can look for a password where it must never be."""
import os
import stat

from contract.root_tests.fakes.loopback_ssh import SshServer

PASSWORD = "Fake-Sudo-Pw-7c41e9"
BASE_ANSWER = "os=Linux\narch=x86_64\nuser=build\nhome=/home/build\nversion=Ubuntu 24.04.1 LTS\nchip=Intel Xeon\ncpu=8\nram_mb=32108\nkvm=yes\ndisk_free_gb=412\ntool=curl\npkg=apt\nsudo=password\nport_9101=free\n"
WINDOWS_ERROR = "'sh' is not recognized as an internal or external command,\r\noperable program or batch file.\r\n"

DISPATCH = """#!/bin/sh
DIR='{dir}'
PATH="$DIR/bin:$PATH"; export PATH
[ "$(command -v sudo)" = "$DIR/bin/sudo" ] || exit 99
case "$SSH_ORIGINAL_COMMAND" in
  "sh -s")
    cat >/dev/null
    if [ -e "$DIR/state/windows" ]; then printf '%s' "$(cat "$DIR/windows_error.txt")" >&2; exit 1; fi
    cat "$DIR/answer.txt"
    [ -e "$DIR/state/incus" ] && echo tool=incus
    [ -e "$DIR/state/python3" ] && echo tool=python3
    exit 0 ;;
  *) exec sh -c "$SSH_ORIGINAL_COMMAND" ;;
esac
"""

SUDO = """#!/bin/sh
DIR='{dir}'
env >> "$DIR/sudo_env.log"
mode=n
while [ $# -gt 0 ]; do
  case "$1" in -S) mode=S ;; -n) mode=n ;; -p) shift ;; --) shift; break ;; *) break ;; esac
  shift
done
echo "sudo mode=$mode" >> "$DIR/commands.log"
if [ -e "$DIR/state/sudo_denied" ]; then echo "build is not in the sudoers file.  This incident will be reported." >&2; exit 1; fi
if [ "$mode" = S ]; then
  IFS= read -r given || given=""
  if [ "$given" != "$(cat "$DIR/sudo_password")" ]; then echo "Sorry, try again." >&2; echo "sudo: 1 incorrect password attempt" >&2; exit 1; fi
elif [ ! -e "$DIR/state/passwordless" ]; then echo "sudo: a password is required" >&2; exit 1; fi
FAKE_ROOT=1 exec "$@"
"""

APT_GET = """#!/bin/sh
DIR='{dir}'
echo "apt-get $*" >> "$DIR/commands.log"
[ -n "$FAKE_ROOT" ] || exit 100
case "$DEBIAN_FRONTEND" in noninteractive) ;; *) echo "E: not noninteractive" >&2; exit 100 ;; esac
if [ -e "$DIR/state/apt_lock" ]; then echo "E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 812 (unattended-upgr)" >&2; exit 100; fi
if [ -e "$DIR/state/no_network" ]; then echo "Err:1 http://archive.ubuntu.com noble InRelease  Temporary failure resolving 'archive.ubuntu.com'" >&2; exit 100; fi
case "$*" in
  *"install incus"*) touch "$DIR/state/incus" ;;
  *"install python3"*) touch "$DIR/state/python3" ;;
esac
exit 0
"""

APT_CACHE = """#!/bin/sh
if [ -e '{dir}/state/no_candidate' ]; then printf '  Installed: (none)\\n  Candidate: (none)\\n'; else printf '  Installed: (none)\\n  Candidate: 6.0.0-1ubuntu1\\n'; fi
"""

INCUS = """#!/bin/sh
DIR='{dir}'
echo "incus $*" >> "$DIR/commands.log"
case "$*" in
  "admin waitready"*) exit 0 ;;
  "profile device list default") [ -e "$DIR/state/initialised" ] && printf 'root\\neth0\\n'; exit 0 ;;
  "admin init --minimal") touch "$DIR/state/initialised"; exit 0 ;;
esac
exit 0
"""

SIMPLE = {
    "usermod": '#!/bin/sh\necho "usermod $*" >> \'{dir}/commands.log\'\ntouch \'{dir}/state/in_group\'\n',
    "getent": "#!/bin/sh\necho 'incus-admin:x:999:'\n",
    "id": '#!/bin/sh\nif [ "$1" = -u ] && [ -n "$FAKE_ROOT" ]; then echo 0; exit 0; fi\nexec /usr/bin/id "$@"\n',
    "sleep": "#!/bin/sh\nexit 0\n",
}


class FakeLinux(SshServer):
    """`state(name)` switches a behaviour on: sudo_denied, passwordless, apt_lock, no_network, no_candidate, windows, initialised."""

    def __init__(self, password=PASSWORD):
        super().__init__(answer=None)
        self.password = password
        os.makedirs(os.path.join(self.dir, "state"))
        os.makedirs(os.path.join(self.dir, "bin"))
        self._file("answer.txt", BASE_ANSWER)
        self._file("windows_error.txt", WINDOWS_ERROR)
        self._file("sudo_password", password)
        self._file("dispatch.sh", DISPATCH, executable=True)
        for name, template in {"sudo": SUDO, "apt-get": APT_GET, "apt-cache": APT_CACHE, "incus": INCUS, **SIMPLE}.items():
            self._file(os.path.join("bin", name), template, executable=True)
        with open(os.path.join(self.dir, "sshd_config"), "a") as config:
            config.write(f"ForceCommand sh {self.dir}/dispatch.sh\n")

    def _file(self, name, template, executable=False):
        path = os.path.join(self.dir, name)
        with open(path, "w") as file:
            file.write(template.replace("{dir}", self.dir))
        if executable:
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

    def state(self, name, on=True):
        path = os.path.join(self.dir, "state", name)
        if on:
            open(path, "w").close()
        elif os.path.exists(path):
            os.remove(path)

    def has(self, name):
        return os.path.exists(os.path.join(self.dir, "state", name))

    def commands(self):
        path = os.path.join(self.dir, "commands.log")
        return open(path).read() if os.path.exists(path) else ""

    def environment_seen_by_sudo(self):
        path = os.path.join(self.dir, "sudo_env.log")
        return open(path).read() if os.path.exists(path) else ""
