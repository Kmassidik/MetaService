import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SERVICE = os.path.join(ROOT, "scripts", "parent-service.sh")


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class ServiceCase(unittest.TestCase):
    """A fake parent (a tiny web server) in a throw-away folder. The real parent is never touched."""

    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="ms-service-")
        self.token = "fakeparent-" + os.path.basename(self.folder)
        self.served = os.path.join(self.folder, self.token)
        os.makedirs(self.served)
        self.port = free_port()
        self.program = os.path.join(self.folder, "fake-parent.sh")
        self.write_program(f'#!/bin/sh\necho "fake parent says hello"\nexec {sys.executable} -m http.server {self.port} --bind 127.0.0.1 --directory {self.served}\n')
        self.env = {**os.environ, "METASERVICE_RUN_DIR": os.path.join(self.folder, "run"), "METASERVICE_PARENT_COMMAND": self.program, "METASERVICE_SKIP_BUILD": "1",
                    "METASERVICE_PANEL_URL": f"http://127.0.0.1:{self.port}", "METASERVICE_PROCESS_PATTERN": self.token, "METASERVICE_WAIT_SECONDS": "20",
                    }
        self.addCleanup(self.cleanup)

    def write_program(self, text):
        with open(self.program, "w") as file:
            file.write(text)
        os.chmod(self.program, 0o755)

    def cleanup(self):
        subprocess.run(["pkill", "-f", self.token], capture_output=True)
        subprocess.run(["rm", "-rf", self.folder])

    def service(self, *arguments, **env):
        return subprocess.run(["sh", SERVICE, *arguments], capture_output=True, text=True, env={**self.env, **env}, timeout=90)

    def listening(self):
        with socket.socket() as probe:
            probe.settimeout(1)
            return probe.connect_ex(("127.0.0.1", self.port)) == 0

    def pid(self):
        with open(os.path.join(self.folder, "run", "parent.pid")) as file:
            return int(file.read())

    def gone(self, pid, seconds=10):
        for _ in range(seconds * 10):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            time.sleep(0.1)
        return False


class BackgroundTest(ServiceCase):
    def test_start_runs_it_in_the_background_and_stop_ends_it(self):
        started = self.service("start")
        self.assertEqual(started.returncode, 0, started.stdout + started.stderr)
        self.assertIn("running in the background", started.stdout)
        self.assertTrue(self.listening())
        pid = self.pid()
        stopped = self.service("stop")
        self.assertIn("is stopped", stopped.stdout)
        self.assertTrue(self.gone(pid))
        self.assertFalse(self.listening())
        self.assertFalse(os.path.exists(os.path.join(self.folder, "run", "parent.pid")))

    def test_the_run_folder_is_private_and_the_log_holds_what_it_said(self):
        self.service("start")
        run = os.path.join(self.folder, "run")
        self.assertEqual(os.stat(run).st_mode & 0o077, 0)
        self.assertEqual(os.stat(os.path.join(run, "parent.log")).st_mode & 0o077, 0)
        self.assertIn("fake parent says hello", self.service("logs").stdout)

    def test_starting_twice_does_not_start_a_second_one(self):
        self.service("start")
        pid = self.pid()
        again = self.service("start")
        self.assertIn("already running", again.stdout)
        self.assertIn(str(pid), again.stdout)
        self.assertEqual(self.pid(), pid)

    def test_status_says_running_or_not(self):
        self.assertIn("not running", self.service("status").stdout)
        self.service("start")
        running = self.service("status").stdout
        self.assertIn(f"pid {self.pid()}", running)
        self.service("stop")
        self.assertIn("not running", self.service("status").stdout)

    def test_stop_with_nothing_running_says_so(self):
        self.assertIn("not running", self.service("stop").stdout)

    def test_logs_before_the_first_start_say_there_is_no_log(self):
        self.assertIn("No log yet", self.service("logs").stdout)

    def test_a_parent_that_dies_at_once_is_reported_with_its_own_words(self):
        self.write_program('#!/bin/sh\necho "cannot bind the port"\nexit 1\n')
        failed = self.service("start")
        self.assertEqual(failed.returncode, 1)
        self.assertIn("did not come up", failed.stdout)
        self.assertIn("cannot bind the port", failed.stdout)

    def test_one_that_was_not_started_here_is_still_found_and_stopped(self):
        other = subprocess.Popen([sys.executable, "-m", "http.server", str(self.port), "--bind", "127.0.0.1", "--directory", self.served], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (other.poll() is None and other.send_signal(signal.SIGKILL), other.wait()))
        for _ in range(50):
            if self.listening():
                break
            time.sleep(0.1)
        self.assertIn(f"pid {other.pid}", self.service("status").stdout)
        self.assertIn("already running", self.service("start").stdout)
        self.service("stop")
        self.assertIsNotNone(other.wait(timeout=10), "the parent that was not started here is still running")  # wait() also reaps it, as its owner would


class BuildOutputTest(ServiceCase):
    """The build step is quiet: the compiler's warnings go to a log, and show only when the build fails."""

    def setUp(self):
        super().setUp()
        del self.env["METASERVICE_SKIP_BUILD"]
        self.noise = "warning: converting non-Sendable function value (pretend compiler noise)"
        self.write_build_program("exit 0")

    def write_build_program(self, build_ending):
        self.write_program(f'#!/bin/sh\nif [ -n "$METASERVICE_BUILD_ONLY" ]; then\n  echo "{self.noise}"\n  echo "Build step ran"\n  {build_ending}\nfi\n'
                           f'exec {sys.executable} -m http.server {self.port} --bind 127.0.0.1 --directory {self.served}\n')

    def test_the_compiler_output_goes_to_the_log_and_not_to_the_screen(self):
        done = self.service("start")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn(self.noise, done.stdout + done.stderr)
        self.assertIn("Building MetaService", done.stdout)
        self.assertIn("build.log", done.stdout)
        with open(os.path.join(self.folder, "run", "build.log")) as file:
            self.assertIn(self.noise, file.read())
        self.assertTrue(self.listening())

    def test_a_failed_build_shows_what_it_said_and_starts_nothing(self):
        self.write_build_program('echo "error: cannot find the thing"; exit 1')
        done = self.service("start")
        self.assertEqual(done.returncode, 1)
        self.assertIn("The build failed", done.stdout)
        self.assertIn("error: cannot find the thing", done.stdout)
        self.assertFalse(self.listening())
        self.assertFalse(os.path.exists(os.path.join(self.folder, "run", "parent.pid")))

    def test_the_build_log_is_private(self):
        self.service("start")
        self.assertEqual(os.stat(os.path.join(self.folder, "run", "build.log")).st_mode & 0o077, 0)


if __name__ == "__main__":
    unittest.main()
