import os
import pty
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from test_parent_service import ServiceCase  # noqa: E402

REPO = os.path.join(os.path.dirname(__file__), "..", "..")
UNINSTALL = os.path.join(REPO, "scripts", "uninstall.sh")

GENERATED = ["control-plane/arm64/.build", "agent/macos/.build", "agent/linux/target", "shared/metaservice-shared/.build", "frontend/node_modules", "bundles/chat/ui/node_modules",
             "control-plane/arm64/run", "control-plane/arm64/state", "logs", "scripts/__pycache__"]
KEPT = ["install.sh", "control-plane/arm64/.env", "control-plane/arm64/Package.swift", "frontend/src/App.svelte", ".git/HEAD", "README.md"]


def make_tree():
    """A pretend MetaService folder with what the installer makes and what must survive. Nothing here is the real folder."""
    root = tempfile.mkdtemp(prefix="ms-uninstall-")
    for path in GENERATED:
        os.makedirs(os.path.join(root, path))
        with open(os.path.join(root, path, "file.bin"), "w") as file:
            file.write("x" * 2048)
    for path in KEPT:
        os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        with open(os.path.join(root, path), "w") as file:
            file.write("keep me")
    return root


def exists(root, path):
    return os.path.exists(os.path.join(root, path))


class UninstallBase(ServiceCase):
    def setUp(self):
        super().setUp()
        self.root = make_tree()
        self.addCleanup(shutil.rmtree, self.root, True)
        self.env = {**self.env, "METASERVICE_ROOT": self.root}

    def uninstall(self, *arguments):
        return subprocess.run(["sh", UNINSTALL, *arguments], capture_output=True, text=True, env=self.env, stdin=subprocess.DEVNULL, timeout=90)

    def at_the_keyboard(self, typed):
        master, slave = pty.openpty()
        running = subprocess.Popen(["sh", UNINSTALL], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=self.env)
        os.close(slave)
        os.write(master, typed.encode())
        out, err = running.communicate(timeout=60)
        os.close(master)
        return running.returncode, out, err


class RemovalTest(UninstallBase):
    def test_everything_it_made_is_removed_and_everything_of_yours_stays(self):
        done = self.uninstall("--yes")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        for path in GENERATED:
            self.assertFalse(exists(self.root, path), f"{path} was not removed")
        for path in KEPT:
            self.assertTrue(exists(self.root, path), f"{path} was removed but must stay")
        self.assertIn("Removed.", done.stdout)

    def test_it_lists_what_it_will_remove_with_sizes_before_removing(self):
        done = self.uninstall("--yes")
        for word in ("builds", "packages", "your data", "Python caches", " KB "):
            self.assertIn(word, done.stdout)
        self.assertIn("It keeps: the source code and git, Apple's container tool, nmap, and your .env settings.", done.stdout)

    def test_keep_data_leaves_the_state_folder(self):
        self.uninstall("--yes", "--keep-data")
        self.assertTrue(exists(self.root, "control-plane/arm64/state/file.bin"))
        self.assertFalse(exists(self.root, "control-plane/arm64/.build"))

    def test_the_env_file_goes_only_when_asked_for(self):
        self.uninstall("--yes")
        self.assertTrue(exists(self.root, "control-plane/arm64/.env"))
        self.uninstall("--yes", "--env")
        self.assertFalse(exists(self.root, "control-plane/arm64/.env"))
        self.assertTrue(exists(self.root, "install.sh"))

    def test_with_nothing_to_remove_it_says_so(self):
        self.uninstall("--yes")
        again = self.uninstall("--yes")
        self.assertEqual(again.returncode, 0)
        self.assertIn("Nothing to remove", again.stdout)

    def test_a_bad_option_is_refused_and_nothing_is_removed(self):
        done = self.uninstall("--everything")
        self.assertEqual(done.returncode, 2)
        self.assertTrue(exists(self.root, "control-plane/arm64/state/file.bin"))


class RemoteAccessTest(UninstallBase):
    """What was made for reaching the panel from outside must be taken away first: its record lives in the state folder that goes."""

    def setUp(self):
        super().setUp()
        self.agents = tempfile.mkdtemp(prefix="ms-agents-")
        self.addCleanup(shutil.rmtree, self.agents, True)
        self.env = {**self.env, "METASERVICE_LAUNCHCTL": "/usr/bin/true", "METASERVICE_AGENTS_DIR": self.agents}
        self.plist = os.path.join(self.agents, "io.metaservice.cloudflared.plist")
        with open(self.plist, "w") as file:
            file.write("<plist/>")
        record = os.path.join(self.root, "control-plane/arm64/state/remote-access.json")
        with open(record, "w") as file:
            file.write('{"host": "meta.example.com", "tunnel_name": "metaservice", "tunnel_id": "x", "dns_record_id": "y"}')

    def test_it_says_it_will_remove_remote_access_and_tries_to_before_the_state_goes(self):
        done = self.uninstall("--yes")
        self.assertIn("It also removes remote access", done.stdout)
        self.assertIn("Removing remote access", done.stdout)

    def test_when_the_tunnel_cannot_be_removed_it_still_stops_the_connector_and_names_what_to_clean_by_hand(self):
        done = self.uninstall("--yes")
        self.assertIn("could not be fully removed", done.stdout)
        self.assertIn("tunnel: metaservice", done.stdout)
        self.assertIn("host: meta.example.com", done.stdout)
        self.assertFalse(os.path.exists(self.plist), "the connector job file must go")
        self.assertFalse(exists(self.root, "control-plane/arm64/state"))
        self.assertEqual(done.returncode, 0)

    def test_nothing_about_remote_access_is_said_when_none_was_made(self):
        os.remove(os.path.join(self.root, "control-plane/arm64/state/remote-access.json"))
        done = self.uninstall("--yes")
        self.assertNotIn("remote access", done.stdout.lower())
        self.assertTrue(os.path.exists(self.plist), "a job file this tool did not record is not touched")


class SafetyTest(UninstallBase):
    def test_without_a_keyboard_and_without_yes_nothing_is_removed(self):
        done = self.uninstall()
        self.assertEqual(done.returncode, 1)
        self.assertIn("No keyboard to ask on", done.stdout)
        self.assertTrue(exists(self.root, "control-plane/arm64/state/file.bin"))

    def test_a_folder_that_is_not_metaservice_is_refused(self):
        other = tempfile.mkdtemp(prefix="ms-not-mine-")
        self.addCleanup(shutil.rmtree, other, True)
        os.makedirs(os.path.join(other, "frontend", "node_modules"))
        done = subprocess.run(["sh", UNINSTALL, "--yes"], capture_output=True, text=True, env={**self.env, "METASERVICE_ROOT": other}, stdin=subprocess.DEVNULL)
        self.assertEqual(done.returncode, 1)
        self.assertIn("is not a MetaService folder", done.stdout)
        self.assertTrue(os.path.isdir(os.path.join(other, "frontend", "node_modules")))

    def test_the_home_folder_and_the_top_of_the_disk_are_refused(self):
        for target in (os.path.expanduser("~"), "/"):
            done = subprocess.run(["sh", UNINSTALL, "--yes"], capture_output=True, text=True, env={**self.env, "METASERVICE_ROOT": target}, stdin=subprocess.DEVNULL)
            self.assertEqual(done.returncode, 1, target)
            self.assertIn("Nothing was removed", done.stdout, target)

    def test_answering_anything_but_yes_removes_nothing(self):
        for answer in ("no\n", "y\n", "\n"):
            code, out, _ = self.at_the_keyboard(answer)
            self.assertEqual(code, 0, answer)
            self.assertIn("Nothing was removed.", out, answer)
            self.assertTrue(exists(self.root, "control-plane/arm64/state/file.bin"), answer)

    def test_yes_then_no_removes_everything_but_keeps_the_env_file(self):
        code, out, _ = self.at_the_keyboard("yes\nn\n")
        self.assertEqual(code, 0)
        self.assertFalse(exists(self.root, "control-plane/arm64/state"))
        self.assertTrue(exists(self.root, "control-plane/arm64/.env"))

    def test_yes_then_yes_also_removes_the_env_file(self):
        self.at_the_keyboard("yes\ny\n")
        self.assertFalse(exists(self.root, "control-plane/arm64/.env"))
        self.assertTrue(exists(self.root, "README.md"))


class StopsFirstTest(UninstallBase):
    def test_a_running_parent_is_stopped(self):
        self.assertEqual(self.service("start").returncode, 0)
        pid = self.pid()
        done = self.uninstall("--yes")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertTrue(self.gone(pid), "the parent was still running after the uninstall")
        self.assertFalse(self.listening())


if __name__ == "__main__":
    unittest.main()
