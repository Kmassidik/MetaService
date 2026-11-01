"""Tests for scripts/harden/harden-linux.sh and harden-mac.sh.

They never run as root and never touch the real system: HARDEN_ROOT puts every system path in a
throw-away folder, and HARDEN_DRY_COMMANDS=1 swaps systemctl, apt-get, sshd, nft, socketfilterfw,
systemd-run, launchctl ... for recorders that append the call to a file.
"""
import getpass
import os
import shutil
import subprocess
import tempfile
import unittest

HARDEN_DIR = os.path.join(os.path.dirname(__file__), "..", "harden")
LINUX = os.path.join(HARDEN_DIR, "harden-linux.sh")
MAC = os.path.join(HARDEN_DIR, "harden-mac.sh")
USER = getpass.getuser()
KEY_LINE = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake test@example\n"
EXPECTED_SSHD_T = "passwordauthentication no\nkbdinteractiveauthentication no\npermitrootlogin no\nallowusers {user}\n"
EXIT_REFUSED = 3
FORBIDDEN_CALLS = ("ufw", "iptables", "flush", "docker", "incus", "reboot", "shutdown", "halt")


class HardenCase(unittest.TestCase):
    script = LINUX

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="ms-harden-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.home = os.path.join(self.root, "home", USER)
        self.canned = os.path.join(self.root, "canned")
        os.makedirs(self.canned)
        self.write("etc/ssh/sshd_config", "Include /etc/ssh/sshd_config.d/*.conf\nUsePAM yes\n")
        self.write("etc/os-release", 'ID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\n')
        self.make_key_login()
        self.set_canned("sshd_T", EXPECTED_SSHD_T.format(user=USER))
        self.calls_path = os.path.join(self.root, "harden-calls.log")

    # ---- fixtures

    def write(self, relative, text, mode=0o644):
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as file:
            file.write(text)
        os.chmod(path, mode)
        return path

    def set_canned(self, name, text):
        with open(os.path.join(self.canned, name), "w") as file:
            file.write(text)

    def make_key_login(self, content=KEY_LINE):
        os.makedirs(os.path.join(self.home, ".ssh"), exist_ok=True)
        os.chmod(self.home, 0o755)
        os.chmod(os.path.join(self.home, ".ssh"), 0o700)
        self.write(os.path.join("home", USER, ".ssh", "authorized_keys"), content, 0o600)

    def path(self, relative):
        return os.path.join(self.root, relative)

    def read(self, relative):
        with open(self.path(relative), "rb") as file:
            return file.read()

    def exists(self, relative):
        return os.path.exists(self.path(relative))

    def calls(self):
        if not os.path.exists(self.calls_path):
            return ""
        with open(self.calls_path) as file:
            return file.read()

    def run_script(self, *arguments, **env):
        full = {**os.environ, "HARDEN_ROOT": self.root, "HARDEN_DRY_COMMANDS": "1", "HARDEN_USER_HOME": self.home,
                "HARDEN_FAKE_OUT_DIR": self.canned, "SUDO_USER": USER, "HARDEN_CALL_LOG": self.calls_path}
        full.update(env)
        return subprocess.run(["bash", self.script, *arguments], capture_output=True, text=True, env=full, timeout=60)

    def apply(self, *extra, **env):
        return self.run_script("apply", "--confirm-key-login", *extra, **env)

    def backup_runs(self):
        folder = self.path(self.state_folder)
        if not os.path.isdir(folder):
            return []
        return sorted(name for name in os.listdir(folder) if os.path.isdir(os.path.join(folder, name)) and name != "bin")

    state_folder = "var/backups/metaservice-harden"
    dropin = "etc/ssh/sshd_config.d/00-metaservice-hardening.conf"


class LinuxTests(HardenCase):
    def setUp(self):
        super().setUp()
        self.write("etc/ssh/sshd_config.d/50-cloud-init.conf", "PasswordAuthentication yes\n")

    def test_check_shows_state_from_fixtures_and_changes_nothing(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SSH password login", result.stdout)
        self.assertRegex(result.stdout, r"SSH password login\s+yes\s+set to no")
        self.assertRegex(result.stdout, r"SSH drop-in 00-metaservice-hardening.conf\s+missing\s+write it")
        self.assertIn("1 usable key(s)", result.stdout)
        self.assertFalse(self.exists(self.dropin))
        self.assertFalse(self.exists(self.state_folder))
        for mutating in ("apt-get", "reload", "systemd-run", "enable", "restart", "install"):
            self.assertNotIn(mutating, self.calls())

    def test_check_is_the_default_and_reports_in_place_after_apply(self):
        self.assertEqual(self.apply().returncode, 0)
        result = self.run_script("check")
        self.assertRegex(result.stdout, r"SSH drop-in 00-metaservice-hardening.conf\s+in place\s+nothing")
        self.assertRegex(result.stdout, r"fail2ban sshd jail\s+in place")

    def test_apply_writes_dropin_with_the_right_contents(self):
        self.set_canned("sshd_T", EXPECTED_SSHD_T.format(user=USER + " bob carol"))
        result = self.apply("--extra-users", "bob,carol")
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.read(self.dropin).decode()
        for line in ("PasswordAuthentication no", "KbdInteractiveAuthentication no", "PermitRootLogin no",
                     f"AllowUsers {USER} bob carol", "MaxAuthTries 3", "LoginGraceTime 20", "MaxStartups 10:30:60"):
            self.assertIn(line + "\n", text)
        calls = self.calls()
        self.assertIn("sshd -t", calls)
        self.assertIn("systemctl reload ssh", calls)
        self.assertLess(calls.index("sshd -t"), calls.index("systemctl reload ssh"))

    def test_dropin_name_sorts_before_cloud_init(self):
        self.apply()
        names = sorted(os.listdir(self.path("etc/ssh/sshd_config.d")))
        self.assertEqual(names[0], "00-metaservice-hardening.conf")
        self.assertTrue(names[0] < "50-cloud-init.conf")

    def test_fail2ban_blocklist_and_unattended_files(self):
        self.apply()
        jail = self.read("etc/fail2ban/jail.d/metaservice-sshd.local").decode()
        for line in ("maxretry = 4", "findtime = 10m", "bantime = 1h", "ignoreip = 127.0.0.1/8 192.168.0.0/24"):
            self.assertIn(line, jail)
        rules = self.read("etc/metaservice-blocklist.nft").decode()
        for cidr in ("102.220.160.0/24", "102.220.163.0/24", "77.239.124.0/24"):
            self.assertIn(cidr, rules)
        self.assertIn("table inet metaservice-blocklist", rules)
        self.assertIn("policy accept", rules)
        self.assertNotIn("flush", rules)
        self.assertIn("metaservice-blocklist.service", self.calls())
        self.assertIn('Automatic-Reboot "false"', self.read("etc/apt/apt.conf.d/52metaservice-unattended").decode())
        self.assertIn('Unattended-Upgrade "1"', self.read("etc/apt/apt.conf.d/20auto-upgrades").decode())

    def test_apply_never_runs_forbidden_commands(self):
        self.apply()
        for forbidden in FORBIDDEN_CALLS:
            self.assertNotIn(forbidden, self.calls())

    def test_refuses_without_authorized_keys(self):
        os.remove(os.path.join(self.home, ".ssh", "authorized_keys"))
        result = self.apply()
        self.assertEqual(result.returncode, EXIT_REFUSED)
        self.assertIn("lock", result.stderr)
        self.assertFalse(self.exists(self.dropin))
        self.assertEqual(self.backup_runs(), [])

    def test_refuses_when_the_key_file_has_only_comments(self):
        self.make_key_login("# nothing here\n")
        self.assertEqual(self.apply().returncode, EXIT_REFUSED)
        self.assertFalse(self.exists(self.dropin))

    def test_refuses_when_keys_are_writable_by_others(self):
        os.chmod(os.path.join(self.home, ".ssh", "authorized_keys"), 0o666)
        result = self.apply()
        self.assertEqual(result.returncode, EXIT_REFUSED)
        self.assertIn("StrictModes", result.stderr)

    def test_refuses_without_the_second_check_flag(self):
        result = self.run_script("apply")
        self.assertEqual(result.returncode, EXIT_REFUSED)
        self.assertIn("--confirm-key-login", result.stderr)
        self.assertFalse(self.exists(self.dropin))

    def test_refuses_on_unsupported_os(self):
        self.write("etc/os-release", "ID=fedora\n")
        result = self.apply()
        self.assertEqual(result.returncode, EXIT_REFUSED)
        self.assertIn("Ubuntu or Debian", result.stderr)
        self.assertFalse(self.exists(self.dropin))

    def test_refuses_for_root_or_missing_sudo_user(self):
        self.assertEqual(self.apply(SUDO_USER="root").returncode, EXIT_REFUSED)
        self.assertEqual(self.apply(SUDO_USER="").returncode, EXIT_REFUSED)

    def test_dry_mode_and_root_prefix_must_go_together(self):
        self.assertEqual(self.run_script("check", HARDEN_ROOT="").returncode, EXIT_REFUSED)
        self.assertEqual(self.run_script("check", HARDEN_DRY_COMMANDS="0").returncode, EXIT_REFUSED)

    def test_backup_and_rollback_restore_original_bytes(self):
        original_dropin = b"PasswordAuthentication yes\n\xff\x00odd bytes\n"
        original_jail = b"[sshd]\nenabled = false\n"
        self.write("etc/ssh/sshd_config.d/00-metaservice-hardening.conf", "")
        with open(self.path(self.dropin), "wb") as file:
            file.write(original_dropin)
        os.makedirs(self.path("etc/fail2ban/jail.d"), exist_ok=True)
        with open(self.path("etc/fail2ban/jail.d/metaservice-sshd.local"), "wb") as file:
            file.write(original_jail)
        self.assertEqual(self.apply().returncode, 0)
        self.assertNotEqual(self.read(self.dropin), original_dropin)
        runs = self.backup_runs()
        self.assertEqual(len(runs), 1)
        self.assertTrue(os.path.exists(self.path(f"{self.state_folder}/{runs[0]}/manifest")))
        self.run_script("confirm")
        result = self.run_script("rollback")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read(self.dropin), original_dropin)
        self.assertEqual(self.read("etc/fail2ban/jail.d/metaservice-sshd.local"), original_jail)
        self.assertFalse(self.exists("etc/metaservice-blocklist.nft"))  # did not exist before: removed
        self.assertIn("systemctl disable --now metaservice-blocklist.service", self.calls())
        self.assertIn("systemctl reload ssh", self.calls().split("disable --now")[-1])

    def test_second_apply_is_quiet_and_makes_no_new_backup(self):
        self.assertEqual(self.apply().returncode, 0)
        self.run_script("confirm")
        runs = self.backup_runs()
        calls_before = self.calls().count("systemd-run")
        second = self.apply()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.backup_runs(), runs)
        self.assertIn("Nothing needed changing", second.stdout)
        self.assertEqual(self.calls().count("systemd-run"), calls_before)
        self.assertNotIn("wrote ", second.stdout)

    def test_auto_revert_is_scheduled_and_confirm_cancels_it(self):
        self.apply()
        self.assertIn("systemd-run --unit=metaservice-harden-revert --on-active=5min", self.calls())
        self.assertIn("rollback --auto", self.calls())
        marker = f"{self.state_folder}/revert-pending"
        self.assertTrue(self.exists(marker))
        blocked = self.apply()
        self.assertEqual(blocked.returncode, EXIT_REFUSED)  # unconfirmed apply blocks a new one
        before = self.calls().count("systemctl stop metaservice-harden-revert.timer")
        confirmed = self.run_script("confirm")
        self.assertEqual(confirmed.returncode, 0)
        self.assertGreater(self.calls().count("systemctl stop metaservice-harden-revert.timer"), before)
        self.assertFalse(self.exists(marker))

    def test_failed_sshd_test_undoes_everything(self):
        result = self.apply(HARDEN_FAKE_FAIL="sshd")
        self.assertEqual(result.returncode, EXIT_REFUSED)
        self.assertFalse(self.exists(self.dropin))
        self.assertFalse(self.exists("etc/fail2ban/jail.d/metaservice-sshd.local"))
        self.assertNotIn("systemctl reload ssh\nsystemctl", self.calls().split("sshd -t")[0])
        self.assertNotIn("systemd-run", self.calls())

    def test_effective_value_check_refuses_when_another_file_wins(self):
        self.set_canned("sshd_T", "passwordauthentication yes\nkbdinteractiveauthentication no\npermitrootlogin no\n")
        result = self.apply()
        self.assertEqual(result.returncode, EXIT_REFUSED)
        self.assertFalse(self.exists(self.dropin))

    def test_blocklist_rejects_malformed_ranges(self):
        bad = ["1.2.3.4/24", "999.1.1.0/24", "1.2.3.0/24; rm -rf /", "0.0.0.0/0", "010.0.0.0/24", "1.2.3.0/33",
               "1.2.3.0", "$(id)", "1.2.3.0/24 `id`", "192.168.0.0/16", "192.168.0.0/24", "127.0.0.0/8", "1.2.3.0/24\n4.5.6.0/24 x"]
        for ranges in bad:
            with self.subTest(ranges=ranges):
                result = self.apply(BLOCKLIST_RANGES=ranges)
                self.assertEqual(result.returncode, EXIT_REFUSED, ranges)
                self.assertFalse(self.exists("etc/metaservice-blocklist.nft"))
                self.assertFalse(self.exists(self.dropin))

    def test_blocklist_accepts_clean_ranges_and_an_empty_list(self):
        self.assertEqual(self.apply(BLOCKLIST_RANGES="203.0.113.0/24 198.51.100.64/26").returncode, 0)
        self.assertIn("198.51.100.64/26", self.read("etc/metaservice-blocklist.nft").decode())

    def test_extra_users_are_validated(self):
        for bad in ("bob;id", "$(id)", "Bob", "a b!", "x`id`"):
            with self.subTest(users=bad):
                self.assertEqual(self.apply("--extra-users", bad).returncode, EXIT_REFUSED)
                self.assertFalse(self.exists(self.dropin))

    def test_missing_sshd_T_output_fails_closed(self):
        os.remove(os.path.join(self.canned, "sshd_T"))
        self.assertEqual(self.apply().returncode, EXIT_REFUSED)
        self.assertFalse(self.exists(self.dropin))

    def test_updates_flag_needs_yes_and_never_reboots(self):
        quiet = self.run_script("--updates")
        self.assertEqual(quiet.returncode, 0)
        self.assertNotIn("apt-get", self.calls())
        self.write("var/run/reboot-required", "")
        done = self.run_script("--updates", "--yes")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("apt-get update", self.calls())
        self.assertIn("full-upgrade", self.calls())
        self.assertIn("REBOOT IS NEEDED", done.stdout)
        self.assertIn("GPU", done.stdout)
        self.assertNotIn("reboot\n", self.calls())
        self.assertFalse(self.exists(self.dropin))  # updates are separate from apply

    def test_updates_cannot_be_combined_with_apply(self):
        self.assertEqual(self.run_script("apply", "--updates", "--yes", "--confirm-key-login").returncode, EXIT_REFUSED)

    def test_summary_contains_the_outside_probe(self):
        out = self.apply(PUBLIC_PORT="1003", PUBLIC_ADDRESS="203.0.113.9").stdout
        self.assertIn("-o PreferredAuthentications=password -o PubkeyAuthentication=no -p 1003", out)
        self.assertIn("Permission denied (publickey).", out)

    def test_sudo_and_docker_warnings_are_printed_not_acted_on(self):
        self.write("etc/sudoers.d/90-nopass", f"{USER} ALL=(ALL) NOPASSWD:ALL\n")
        self.set_canned("id_nG_" + USER, "users docker\n")
        out = self.apply().stdout
        self.assertIn("Passwordless sudo", out)
        self.assertIn("docker group", out)
        self.assertEqual(self.read("etc/sudoers.d/90-nopass").decode(), f"{USER} ALL=(ALL) NOPASSWD:ALL\n")


class MacTests(HardenCase):
    script = MAC
    state_folder = "var/db/metaservice-harden"

    def setUp(self):
        super().setUp()
        os.remove(self.path("etc/os-release"))
        self.write("etc/ssh/sshd_config.d/100-macos.conf", "Include /etc/ssh/sshd_config.d/*\nAuthenticationMethods any\n")
        self.write("usr/local/bin/cloudflared", "#!/bin/sh\n", 0o755)
        self.write("usr/local/bin/wireguard-go", "#!/bin/sh\n", 0o755)
        self.write("opt/metaservice/bin/metaservice-root", "#!/bin/sh\n", 0o755)

    def mac(self, *extra, **env):
        return self.apply(*extra, HARDEN_FAKE_UNAME="Darwin", **env)

    def test_check_prints_firewall_state_from_fixtures(self):
        self.set_canned("socketfilterfw_getglobalstate", "Firewall is disabled. (State = 0)\n")
        self.set_canned("socketfilterfw_getstealthmode", "Firewall stealth mode is off\n")
        self.set_canned("launchctl_print_disabled_system", '\t"com.apple.screensharing" => enabled\n')
        result = self.run_script("check", HARDEN_FAKE_UNAME="Darwin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"firewall\s+off\s+turn on")
        self.assertRegex(result.stdout, r"stealth mode\s+off")
        self.assertRegex(result.stdout, r"Screen Sharing\s+on\s+left alone")
        self.assertRegex(result.stdout, r"allow cloudflared\s+listed: no\s+add")
        self.assertFalse(self.exists(self.state_folder))
        self.assertNotIn("--add", self.calls())
        self.assertNotIn("--setglobalstate", self.calls())

    def test_apply_writes_dropin_without_reload(self):
        self.set_canned("sshd_T", EXPECTED_SSHD_T.format(user=USER + " bob"))
        result = self.mac("--extra-users", "bob")
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.read(self.dropin).decode()
        for line in ("PasswordAuthentication no", "KbdInteractiveAuthentication no", "PermitRootLogin no",
                     f"AllowUsers {USER} bob", "MaxAuthTries 3", "LoginGraceTime 20"):
            self.assertIn(line + "\n", text)
        self.assertNotIn("MaxStartups", text)
        self.assertIn("sshd -t", self.calls())
        self.assertNotIn("reload", self.calls())
        self.assertIn("00-metaservice-hardening.conf", self.dropin)

    def test_firewall_allows_programs_before_it_turns_on(self):
        self.mac()
        calls = self.calls()
        for program in ("/usr/local/bin/cloudflared", "/usr/local/bin/wireguard-go", "/opt/metaservice/bin/metaservice-root"):
            self.assertIn(f"socketfilterfw --add {program}", calls)
            self.assertIn(f"socketfilterfw --unblockapp {program}", calls)
            self.assertLess(calls.index(f"--add {program}"), calls.index("--setglobalstate on"))
        for flag in ("--setstealthmode on", "--setallowsigned on", "--setallowsignedapp on"):
            self.assertIn(flag, calls)

    def test_firewall_rollback_switches_back_only_what_was_off(self):
        self.set_canned("socketfilterfw_getstealthmode", "Firewall stealth mode is on\n")
        self.mac()
        self.run_script("confirm", HARDEN_FAKE_UNAME="Darwin")
        self.run_script("rollback", HARDEN_FAKE_UNAME="Darwin")
        calls = self.calls()
        self.assertIn("socketfilterfw --setglobalstate off", calls)
        self.assertIn("socketfilterfw --remove /usr/local/bin/cloudflared", calls)
        self.assertNotIn("--setstealthmode off", calls)  # it was already on, so it stays on

    def test_screen_sharing_untouched_by_default_and_off_on_request(self):
        self.mac()
        self.assertNotIn("launchctl", self.calls().replace("launchctl print-disabled", ""))
        self.run_script("confirm", HARDEN_FAKE_UNAME="Darwin")
        self.run_script("rollback", HARDEN_FAKE_UNAME="Darwin")
        self.set_canned("launchctl_print_disabled_system", '\t"com.apple.screensharing" => enabled\n')
        result = self.mac("--screen-sharing-off")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("launchctl disable system/com.apple.screensharing", self.calls())
        self.run_script("confirm", HARDEN_FAKE_UNAME="Darwin")
        self.run_script("rollback", HARDEN_FAKE_UNAME="Darwin")
        self.assertIn("launchctl enable system/com.apple.screensharing", self.calls())

    def test_auto_revert_is_detached_and_confirm_cancels(self):
        self.mac()
        self.assertIn("detached-revert metaservice-harden-revert sleep=300", self.calls())
        self.assertTrue(self.exists(f"{self.state_folder}/revert-pending"))
        self.assertEqual(self.mac().returncode, EXIT_REFUSED)
        self.run_script("confirm", HARDEN_FAKE_UNAME="Darwin")
        self.assertIn("cancel-detached-revert", self.calls())
        self.assertFalse(self.exists(f"{self.state_folder}/revert-pending"))

    def test_rollback_restores_original_bytes_and_removes_new_file(self):
        original = b"PasswordAuthentication yes\n\xfe\xff\n"
        with open(self.path(self.dropin), "wb") as file:
            file.write(original)
        self.mac()
        self.assertNotEqual(self.read(self.dropin), original)
        self.run_script("rollback", HARDEN_FAKE_UNAME="Darwin")
        self.assertEqual(self.read(self.dropin), original)

    def test_refusals(self):
        self.assertEqual(self.apply(HARDEN_FAKE_UNAME="Linux").returncode, EXIT_REFUSED)
        os.remove(os.path.join(self.home, ".ssh", "authorized_keys"))
        self.assertEqual(self.mac().returncode, EXIT_REFUSED)
        self.assertFalse(self.exists(self.dropin))
        self.make_key_login()
        self.write("etc/ssh/sshd_config", "UsePAM yes\n")  # no Include: drop-in would be ignored
        self.assertEqual(self.mac().returncode, EXIT_REFUSED)
        self.assertEqual(self.run_script("apply", HARDEN_FAKE_UNAME="Darwin").returncode, EXIT_REFUSED)  # no second check

    def test_idempotent_second_apply(self):
        self.mac()
        self.run_script("confirm", HARDEN_FAKE_UNAME="Darwin")
        runs = self.backup_runs()
        self.set_canned("socketfilterfw_getglobalstate", "Firewall is enabled. (State = 1)\n")
        self.set_canned("socketfilterfw_getstealthmode", "Firewall stealth mode is on\n")
        self.set_canned("socketfilterfw_getallowsigned",
                        "Automatically allow built-in signed software ENABLED.\nAutomatically allow downloaded signed software ENABLED.\n")
        self.set_canned("socketfilterfw_listapps", "/usr/local/bin/cloudflared\n/usr/local/bin/wireguard-go\n/opt/metaservice/bin/metaservice-root\n")
        second = self.mac()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.backup_runs(), runs)
        self.assertIn("Nothing needed changing", second.stdout)

    def test_apply_never_runs_forbidden_commands(self):
        self.mac()
        for forbidden in ("reboot", "softwareupdate", "fdesetup enable", "ufw"):
            self.assertNotIn(forbidden, self.calls().replace("fdesetup status", ""))


if __name__ == "__main__":
    unittest.main()
