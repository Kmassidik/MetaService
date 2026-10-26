import getpass
import http.server
import os
import plistlib
import shutil
import stat
import subprocess
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
AUTOSTART = os.path.join(ROOT, "scripts", "autostart.sh")
INSTALL = os.path.join(ROOT, "install.sh")
PARENT = "io.metaservice.parent"
CONNECTOR = "io.metaservice.connector"
WATCHDOG = "io.metaservice.watchdog"
AGENT = "io.metaservice.cloudflared"
FAKE_LAUNCHCTL = '#!/bin/sh\necho "$@" >> "$FAKE_LAUNCHCTL_LOG"\n[ "$1" = print ] || exit 0\nfor label in $FAKE_LOADED; do\n  [ "$2" = "system/$label" ] && { printf "\\tpid = 4242\\n"; exit 0; }\ndone\nexit 1\n'
FAKE_SUDO = "#!/bin/sh\nexit 1\n"  # sudo never works in these tests: no real sudo is ever called, and the password-less path is the one under test


class Quiet(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, *arguments):
        pass


class AutostartCase(unittest.TestCase):
    """A throw-away MetaService folder, a fake launchctl that records its calls and a fake sudo that always fails. Nothing real is touched."""

    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="ms-autostart-")
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.control_plane = os.path.join(self.folder, "control-plane", "arm64")
        self.daemons = self.make_dir("daemons")
        self.agents = self.make_dir("agents")
        self.calls_log = os.path.join(self.folder, "launchctl.log")
        self.token = os.path.join(self.control_plane, "state", "cloudflared.token")
        self.cloudflared = self.make_script("tools/cloudflared", "#!/bin/sh\n")
        self.binary = self.make_script("control-plane/arm64/.build/debug/metaservice-root", "#!/bin/sh\n")
        self.make_script("bin/sudo", FAKE_SUDO)
        launchctl = self.make_script("bin/launchctl", FAKE_LAUNCHCTL)
        self.write(self.token, "secret-token-value")
        server = http.server.HTTPServer(("127.0.0.1", 0), Quiet)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.env = {**os.environ, "METASERVICE_ROOT": self.folder, "METASERVICE_DAEMONS_DIR": self.daemons, "METASERVICE_AGENTS_DIR": self.agents,
                    "METASERVICE_LAUNCHCTL": launchctl, "FAKE_LAUNCHCTL_LOG": self.calls_log, "FAKE_LOADED": "",
                    "METASERVICE_PANEL_URL": f"http://127.0.0.1:{server.server_port}", "METASERVICE_WAIT_SECONDS": "3",
                    "METASERVICE_CLOUDFLARED": self.cloudflared, "METASERVICE_RUN_DIR": os.path.join(self.folder, "run"), "METASERVICE_LOG_DIR": os.path.join(self.folder, "logs"),
                    "METASERVICE_PROCESS_PATTERN": "no-such-process-" + os.path.basename(self.folder),
                    "PATH": os.path.join(self.folder, "bin") + os.pathsep + os.environ["PATH"]}

    def make_dir(self, name):
        path = os.path.join(self.folder, name)
        os.makedirs(path)
        return path

    def write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as file:
            file.write(text)

    def make_script(self, relative, text):
        path = os.path.join(self.folder, relative)
        self.write(path, text)
        os.chmod(path, 0o755)
        return path

    def autostart(self, *arguments, **env):
        return subprocess.run(["sh", AUTOSTART, *arguments], capture_output=True, text=True, env={**self.env, **env}, timeout=60)

    def calls(self):
        if not os.path.exists(self.calls_log):
            return []
        with open(self.calls_log) as file:
            return file.read().splitlines()

    def plist(self, label):
        with open(os.path.join(self.daemons, label + ".plist"), "rb") as file:
            return plistlib.load(file)

    def position(self, calls, text):
        return next(index for index, call in enumerate(calls) if call.startswith(text))


class PlistTest(AutostartCase):
    def test_the_parent_plist_has_exactly_the_keys_and_values_asked_for(self):
        result = self.autostart("on")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        log = os.path.join(self.folder, "logs", "parent.log")
        self.assertEqual(self.plist(PARENT), {
            "Label": PARENT, "ProgramArguments": [self.binary], "WorkingDirectory": self.control_plane, "UserName": getpass.getuser(),
            "GroupName": "staff", "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10, "StandardOutPath": log, "StandardErrorPath": log,
            "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"]}})

    def test_the_connector_plist_runs_cloudflared_like_the_remote_access_tool(self):
        self.autostart("on")
        job = self.plist(CONNECTOR)
        self.assertEqual(job["ProgramArguments"], [self.cloudflared, "tunnel", "--no-autoupdate", "--protocol", "http2", "run", "--token-file", self.token])
        self.assertEqual(job["UserName"], getpass.getuser())
        self.assertEqual(job["GroupName"], "staff")
        self.assertIs(job["KeepAlive"], True)
        self.assertEqual(job["StandardOutPath"], os.path.join(self.folder, "logs", "cloudflared.log"))
        self.assertNotIn("secret-token-value", repr(job))

    def test_both_plists_follow_the_log_folder_override_and_the_folder_is_private(self):
        elsewhere = os.path.join(self.folder, "elsewhere-logs")
        self.autostart("on", METASERVICE_LOG_DIR=elsewhere)
        self.assertEqual(self.plist(PARENT)["StandardOutPath"], os.path.join(elsewhere, "parent.log"))
        self.assertEqual(self.plist(CONNECTOR)["StandardErrorPath"], os.path.join(elsewhere, "cloudflared.log"))
        self.assertEqual(os.stat(elsewhere).st_mode & 0o777, 0o700)

    def test_every_plist_passes_plutil_lint(self):
        plutil = shutil.which("plutil")
        if not plutil:
            self.skipTest("plutil is not on this computer")
        self.autostart("on")
        for label in (PARENT, CONNECTOR, WATCHDOG):
            path = os.path.join(self.daemons, label + ".plist")
            checked = subprocess.run([plutil, "-lint", path], capture_output=True, text=True)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)

    def test_the_plist_files_are_mode_644(self):
        self.autostart("on")
        for label in (PARENT, CONNECTOR, WATCHDOG):
            self.assertEqual(stat.S_IMODE(os.stat(os.path.join(self.daemons, label + ".plist")).st_mode), 0o644)

    def test_without_a_token_the_connector_is_skipped_and_the_user_job_is_left_alone(self):
        os.remove(self.token)
        result = self.autostart("on")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.daemons, PARENT + ".plist")))
        self.assertFalse(os.path.exists(os.path.join(self.daemons, CONNECTOR + ".plist")))
        self.assertIn(f"skipped {CONNECTOR}", result.stdout)
        self.assertFalse([call for call in self.calls() if AGENT in call])

    def test_without_a_cloudflared_binary_the_connector_is_skipped(self):
        result = self.autostart("on", METASERVICE_CLOUDFLARED=os.path.join(self.folder, "no-cloudflared-here"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.daemons, CONNECTOR + ".plist")))
        self.assertIn("cloudflared was not found", result.stdout)


class RefusalTest(AutostartCase):
    def test_a_missing_build_refuses_and_says_what_to_run(self):
        os.remove(self.binary)
        result = self.autostart("on")
        self.assertEqual(result.returncode, 1)
        self.assertIn("./install.sh install", result.stdout)
        self.assertEqual(os.listdir(self.daemons), [])
        self.assertEqual(self.calls(), [])

    @unittest.skipIf(os.geteuid() == 0, "root can write anywhere")
    def test_when_sudo_cannot_be_used_the_commands_are_printed_and_nothing_is_written(self):
        os.chmod(self.daemons, 0o555)
        self.addCleanup(os.chmod, self.daemons, 0o755)
        result = self.autostart("on")
        self.assertEqual(result.returncode, 1)
        for expected in ("sudo -v", f"sudo install -m 644 -o root -g wheel", f"bootstrap system {self.daemons}/{PARENT}.plist", f"bootstrap system {self.daemons}/{CONNECTOR}.plist"):
            self.assertIn(expected, result.stdout)
        self.assertEqual(os.listdir(self.daemons), [])
        self.assertEqual(self.calls(), [])
        self.assertEqual(os.listdir(self.agents), [])
        self.assertTrue(os.path.exists(os.path.join(self.control_plane, "run", "autostart", PARENT + ".plist")))

    @unittest.skipIf(os.geteuid() == 0, "root can write anywhere")
    def test_off_without_sudo_prints_the_commands_and_removes_nothing(self):
        self.autostart("on")
        os.chmod(self.daemons, 0o555)
        self.addCleanup(os.chmod, self.daemons, 0o755)
        result = self.autostart("off")
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"sudo rm -f {self.daemons}/{PARENT}.plist", result.stdout)
        self.assertTrue(os.path.exists(os.path.join(self.daemons, PARENT + ".plist")))


class HandOverTest(AutostartCase):
    def test_on_hands_over_in_order_and_waits_for_the_panel(self):
        agent_plist = os.path.join(self.agents, AGENT + ".plist")
        self.write(agent_plist, "old user job")
        result = self.autostart("on")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        user_job_out = max(self.position(calls, f"bootout gui/{os.getuid()}/{AGENT}"), self.position(calls, f"bootout user/{os.getuid()}/{AGENT}"))
        self.assertLess(user_job_out, self.position(calls, "bootstrap system"))
        for label in (PARENT, CONNECTOR, WATCHDOG):
            self.assertLess(self.position(calls, f"bootout system/{label}"), self.position(calls, f"bootstrap system {self.daemons}/{label}.plist"))
        self.assertFalse(os.path.exists(agent_plist))
        self.assertIn("Autostart is on", result.stdout)

    def test_on_says_so_when_the_panel_does_not_answer(self):
        result = self.autostart("on", METASERVICE_PANEL_URL="http://127.0.0.1:9", METASERVICE_WAIT_SECONDS="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not answer", result.stdout)

    def test_off_boots_out_and_removes_all_three_and_says_how_to_start_by_hand(self):
        self.autostart("on")
        open(self.calls_log, "w").close()
        result = self.autostart("off")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [f"bootout system/{PARENT}", f"bootout system/{CONNECTOR}", f"bootout system/{WATCHDOG}"])
        self.assertEqual(os.listdir(self.daemons), [])
        self.assertIn("stopped", result.stdout)
        self.assertIn("./install.sh install", result.stdout)

    def test_status_reports_installed_loaded_and_running_for_each(self):
        self.autostart("on")
        loaded = self.autostart("status", FAKE_LOADED=PARENT)
        self.assertIn(f"{PARENT}: installed, loaded, running (pid 4242)", loaded.stdout)
        self.assertIn(f"{CONNECTOR}: installed, NOT loaded", loaded.stdout)
        self.assertIn("The panel answers", loaded.stdout)

    def test_status_with_nothing_installed(self):
        result = self.autostart("status")
        self.assertIn(f"{PARENT}: not installed", result.stdout)
        self.assertIn(f"{CONNECTOR}: not installed", result.stdout)


class InstallScriptTest(AutostartCase):
    def install(self, *arguments):
        return subprocess.run(["sh", INSTALL, *arguments], capture_output=True, text=True, env=self.env, stdin=subprocess.DEVNULL, timeout=60)

    def test_stop_explains_that_autostart_would_restart_it(self):
        self.write(os.path.join(self.daemons, PARENT + ".plist"), "x")
        result = self.install("stop")
        self.assertEqual(result.returncode, 1)
        self.assertIn("autostart off", result.stdout)
        self.assertIn("starts MetaService again", result.stdout)

    def test_stop_without_autostart_still_just_stops(self):
        result = self.install("stop")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("not running", result.stdout)

    def test_install_sh_routes_autostart_and_lists_it_in_help(self):
        self.assertIn("autostart on|off|status", self.install("help").stdout)
        self.assertIn(f"{PARENT}: not installed", self.install("autostart", "status").stdout)

    def test_status_mentions_autostart_only_when_it_is_installed(self):
        self.assertNotIn(PARENT, self.install("status").stdout)
        self.write(os.path.join(self.daemons, PARENT + ".plist"), "x")
        self.assertIn(f"{PARENT}: installed", self.install("status").stdout)


if __name__ == "__main__":
    unittest.main()
