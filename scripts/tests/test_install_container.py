import hashlib
import os
import pty
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from test_parent_service import ServiceCase  # noqa: E402

REPO = os.path.join(os.path.dirname(__file__), "..", "..")
SCRIPT = os.path.join(REPO, "scripts", "install-container.sh")
INSTALL = os.path.join(REPO, "install.sh")
PACKAGE = b"pretend Apple package"
APPLE_SIGNATURE = "Package \"x.pkg\":\n   Status: signed by a developer certificate issued by Apple for distribution\n   Notarization: trusted by the Apple notary service\n   1. Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)\n"
FAKE_CONTAINER = """#!/bin/sh
echo "container $*" >> "$FAKE/calls"
case "$1 $2" in
  "system status") [ -f "$FAKE/running" ] ;;
  "system start") [ -z "$START_FAILS" ] && touch "$FAKE/running" ;;
esac
"""


def script(path, text):
    with open(path, "w") as file:
        file.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class FakeMac:
    """Stand-ins for curl, pkgutil, sudo and Apple's installer, so nothing real is downloaded or installed. Every call is written to `calls`."""

    def __init__(self):
        self.folder = tempfile.mkdtemp(prefix="ms-container-")
        self.bin = os.path.join(self.folder, "bin")
        self.tool = os.path.join(self.folder, "usr-local-bin", "container")
        os.makedirs(self.bin)
        os.makedirs(os.path.dirname(self.tool))
        self.package = os.path.join(self.folder, "fixture.pkg")
        with open(self.package, "wb") as file:
            file.write(PACKAGE)
        script(os.path.join(self.bin, "curl"), '#!/bin/sh\ncase "$*" in\n  *example.invalid*) ;;\n  *) exec /usr/bin/curl "$@" ;;\nesac\necho "curl $*" >> "$FAKE/calls"\n[ -n "$CURL_FAILS" ] && exit 22\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done\ncp "$FAKE/fixture.pkg" "$out"\n')  # only the package download is faked; the panel check goes to the real curl
        script(os.path.join(self.bin, "pkgutil"), '#!/bin/sh\necho "pkgutil $*" >> "$FAKE/calls"\nprintf "%s" "$SIGNATURE"\n')
        script(os.path.join(self.bin, "sudo"), '#!/bin/sh\necho "sudo $*" >> "$FAKE/calls"\nexec "$@"\n')
        script(os.path.join(self.bin, "installer"), f'#!/bin/sh\necho "installer $*" >> "$FAKE/calls"\n[ -n "$INSTALLER_FAILS" ] && exit 1\ncp "$FAKE/container-source" "{self.tool}"\nchmod +x "{self.tool}"\n')
        script(os.path.join(self.folder, "container-source"), FAKE_CONTAINER)
        self.env = {**os.environ, "PATH": self.bin + os.pathsep + os.environ["PATH"], "FAKE": self.folder, "SIGNATURE": APPLE_SIGNATURE,
                    "METASERVICE_CONTAINER_PATHS": self.tool, "METASERVICE_CONTAINER_SHA256": hashlib.sha256(PACKAGE).hexdigest(), "METASERVICE_CONTAINER_URL": "https://example.invalid/x.pkg"}

    def calls(self):
        path = os.path.join(self.folder, "calls")
        if not os.path.exists(path):
            return []
        with open(path) as file:
            return file.read().splitlines()

    def has_tool(self):
        shutil.copy(os.path.join(self.folder, "container-source"), self.tool)
        os.chmod(self.tool, 0o755)

    def start_service(self):
        open(os.path.join(self.folder, "running"), "w").close()


def run(command, env, typing=True):
    """Runs a command with a real terminal on its input (the password prompt needs one), or with none."""
    if not typing:
        done = subprocess.run(command, capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL, timeout=120)
        return done.returncode, done.stdout + done.stderr
    master, slave = pty.openpty()
    running = subprocess.Popen(command, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    os.close(slave)
    out, _ = running.communicate(timeout=120)
    os.close(master)
    return running.returncode, out


class InstallContainerTest(unittest.TestCase):
    def setUp(self):
        self.mac = FakeMac()
        self.addCleanup(shutil.rmtree, self.mac.folder, True)

    def go(self, **extra):
        return run(["sh", SCRIPT], {**self.mac.env, **extra})

    def test_a_missing_tool_is_downloaded_checked_installed_and_started_in_that_order(self):
        code, out = self.go()
        self.assertEqual(code, 0, out)
        calls = self.mac.calls()
        order = [next(i for i, line in enumerate(calls) if line.startswith(start)) for start in ("curl", "pkgutil --check-signature", "sudo installer -pkg ", "container system start --enable-kernel-install")]
        self.assertEqual(order, sorted(order), f"download, then signature, then install, then start: {calls}")
        self.assertTrue(calls[order[2]].endswith("-target /"))
        self.assertIn("✓ Apple's container service is running.", out)

    def test_nothing_is_downloaded_when_the_tool_is_already_there_and_running(self):
        self.mac.has_tool()
        self.mac.start_service()
        code, out = self.go()
        self.assertEqual(code, 0, out)
        self.assertEqual([line for line in self.mac.calls() if not line.startswith("container system status")], [])
        self.assertIn("is installed", out)

    def test_an_installed_tool_whose_service_is_stopped_gets_the_service_started_without_a_download(self):
        self.mac.has_tool()
        code, out = self.go()
        self.assertEqual(code, 0, out)
        self.assertFalse([line for line in self.mac.calls() if line.startswith(("curl", "sudo", "installer"))])
        self.assertIn("container system start --enable-kernel-install", self.mac.calls())

    def test_a_file_that_is_not_the_expected_one_is_refused_and_never_installed(self):
        code, out = self.go(METASERVICE_CONTAINER_SHA256="0" * 64)
        self.assertEqual(code, 1)
        self.assertIn("checksum is different", out)
        self.assertFalse([line for line in self.mac.calls() if line.startswith(("sudo", "installer"))])

    def test_a_package_not_signed_and_notarized_by_apple_is_refused_and_never_installed(self):
        for signature in ("Package \"x.pkg\":\n   Status: no signature\n", APPLE_SIGNATURE.replace("Apple Inc.", "Someone Else"), APPLE_SIGNATURE.replace("trusted by the Apple notary service", "not notarized")):
            code, out = self.go(SIGNATURE=signature)
            self.assertEqual(code, 1, signature)
            self.assertIn("not signed and notarized by Apple", out, signature)
        self.assertFalse([line for line in self.mac.calls() if line.startswith(("sudo", "installer"))])

    def test_a_failed_download_says_so(self):
        code, out = self.go(CURL_FAILS="1")
        self.assertEqual(code, 1)
        self.assertIn("The download failed.", out)
        self.assertFalse([line for line in self.mac.calls() if line.startswith(("sudo", "installer", "pkgutil"))])

    def test_a_refused_password_stops_before_the_service_is_started(self):
        code, out = self.go(INSTALLER_FAILS="1")
        self.assertEqual(code, 1)
        self.assertIn("wrong or cancelled password", out)
        self.assertFalse([line for line in self.mac.calls() if line.startswith("container")])

    def test_a_service_that_will_not_start_gives_the_command_to_run_by_hand(self):
        code, out = self.go(START_FAILS="1")
        self.assertEqual(code, 1)
        self.assertIn("container system start", out)

    def test_without_a_terminal_it_explains_and_downloads_nothing(self):
        code, out = run(["sh", SCRIPT], self.mac.env, typing=False)
        self.assertEqual(code, 1)
        self.assertIn("needs a terminal", out)
        self.assertEqual(self.mac.calls(), [])

    def test_without_a_terminal_an_installed_tool_is_still_fine(self):
        self.mac.has_tool()
        self.mac.start_service()
        self.assertEqual(run(["sh", SCRIPT], self.mac.env, typing=False)[0], 0)

    def test_the_temporary_download_is_deleted_afterwards(self):
        before = set(os.listdir(tempfile.gettempdir()))
        self.go()
        leftovers = [name for name in set(os.listdir(tempfile.gettempdir())) - before if name.startswith("tmp.")]
        self.assertEqual(leftovers, [])


class InstallStepTest(ServiceCase):
    """./install.sh install with the fake Mac and the fake parent: the container step sits between the checks and the build, and can be skipped."""

    def setUp(self):
        super().setUp()
        self.mac = FakeMac()
        self.addCleanup(shutil.rmtree, self.mac.folder, True)
        env_file = os.path.join(self.folder, ".env")
        open(env_file, "w").close()
        os.chmod(env_file, 0o600)
        self.env = {**self.env, **{key: value for key, value in self.mac.env.items() if key not in ("PATH",)}, "PATH": self.mac.env["PATH"], "METASERVICE_ENV_FILE": env_file,
                    "METASERVICE_ROOT": self.folder}

    def install(self, *arguments):
        return run(["sh", INSTALL, *arguments], self.env)

    def test_install_installs_the_missing_tool_before_it_builds_and_starts(self):
        code, out = self.install("install")
        self.assertEqual(code, 0, out)
        self.assertLess(out.index("[3/4] Apple's container tool"), out.index("[4/4] Building and starting"))
        self.assertIn("installer -pkg", " ".join(self.mac.calls()))
        self.assertTrue(self.listening())

    def test_the_nmap_step_follows_the_container_step_and_can_be_skipped(self):
        code, out = self.install("install")
        self.assertEqual(code, 0, out)
        self.assertLess(out.index("[3/4] Apple's container tool"), out.index("nmap (it finds computers"))
        self.assertLess(out.index("nmap (it finds computers"), out.index("[4/4] Building and starting"))
        skipped_code, skipped = self.install("install", "--skip-nmap")
        self.assertEqual(skipped_code, 0, skipped)
        self.assertIn("you chose to go without it", skipped)

    def test_skip_container_goes_without_it_and_says_what_that_costs(self):
        code, out = self.install("install", "--skip-container")
        self.assertEqual(code, 0, out)
        self.assertIn("This Mac cannot create VMs until the tool is installed.", out)
        self.assertEqual(self.mac.calls(), [])
        self.assertTrue(self.listening())

    def test_skip_container_still_uses_a_tool_that_is_already_installed_and_starts_its_service(self):
        self.mac.has_tool()
        code, out = self.install("install", "--skip-container")
        self.assertEqual(code, 0, out)
        self.assertNotIn("Skipped", out)
        self.assertIn("is installed", out)
        self.assertFalse([line for line in self.mac.calls() if line.startswith(("sudo", "installer"))])
        self.assertIn("container system start --enable-kernel-install", self.mac.calls())
        self.assertTrue(self.listening())

    def test_when_the_tool_cannot_be_installed_the_install_stops_and_names_the_way_out(self):
        self.env["INSTALLER_FAILS"] = "1"
        code, out = self.install("install")
        self.assertEqual(code, 1)
        self.assertIn("./install.sh install --skip-container", out)
        self.assertNotIn("[4/4]", out)
        self.assertFalse(self.listening())

    def test_check_only_never_installs_anything(self):
        code, out = self.install("--check")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.mac.calls(), [])
        self.assertNotIn("[3/4]", out)
        self.assertIn("The install adds it for you", out)


if __name__ == "__main__":
    unittest.main()
