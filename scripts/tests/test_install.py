import os
import pty
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
INSTALL = os.path.join(ROOT, "install.sh")


def isolated(folder, env_path):
    """The settings every run here gets, so no test reads or changes the real parent or the real login items."""
    return {**os.environ, "METASERVICE_ENV_FILE": env_path, "METASERVICE_RUN_DIR": os.path.join(folder, "run"), "METASERVICE_LAUNCH_DIR": os.path.join(folder, "LaunchAgents"),
            "METASERVICE_NO_LAUNCHCTL": "1", "METASERVICE_SKIP_BUILD": "1", "METASERVICE_WAIT_SECONDS": "1", "METASERVICE_PROCESS_PATTERN": "no-such-process-" + os.path.basename(folder)}


def with_env_file(env_text, mode=0o600):
    folder = tempfile.mkdtemp(prefix="ms-install-")
    path = os.path.join(folder, ".env")
    with open(path, "w") as file:
        file.write(env_text)
    os.chmod(path, mode)
    return folder, isolated(folder, path)


def install(env_text, *arguments, mode=0o600):
    """Runs ./install.sh with a throw-away .env and no keyboard. Only with --check or a bad .env, so nothing is built or started."""
    folder, env = with_env_file(env_text, mode)
    return subprocess.run(["sh", INSTALL, *arguments], capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)


def at_the_keyboard(typed, env_text=""):
    """Runs ./install.sh with a real terminal, so the menu waits for a choice, and types what it is given. When the typing ends, the menu leaves."""
    folder, env = with_env_file(env_text)
    master, slave = pty.openpty()
    running = subprocess.Popen(["sh", INSTALL], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    os.close(slave)
    os.write(master, typed.encode() + b"\x04")  # \x04 is Ctrl-D: the end of the typing
    out, err = running.communicate(timeout=60)
    os.close(master)
    return running.returncode, out, err


class WelcomeTest(unittest.TestCase):
    def test_it_shows_the_banner_and_the_numbered_steps(self):
        done = install("", "--check")
        self.assertIn("made by Kurnia Massidik", done.stdout)
        self.assertIn("[1/3] Checking the settings", done.stdout)
        self.assertIn("[2/3] Checking this computer", done.stdout)

    def test_the_menu_has_eight_choices_and_does_nothing_without_a_keyboard(self):
        done = install("", )
        self.assertEqual(done.returncode, 0)
        for line in ("1  Help", "2  README", "3  Install", "4  Status", "5  Logs", "6  Stop", "7  Start at login", "8  Quit"):
            self.assertIn(line, done.stdout)
        self.assertNotIn("[1/3]", done.stdout)

    def test_check_only_never_gets_to_the_build_step(self):
        done = install("", "--check")
        self.assertNotIn("[3/3]", done.stdout)
        if done.returncode == 0:
            self.assertIn("Nothing was built or started.", done.stdout)

    def test_the_old_script_name_is_gone_and_the_installer_is_executable(self):
        self.assertFalse(os.path.exists(os.path.join(ROOT, "scripts", "run-control-plane.sh")))
        self.assertTrue(os.access(INSTALL, os.X_OK))


class MenuTest(unittest.TestCase):
    def test_help_and_readme_come_back_to_the_menu_instead_of_closing(self):
        code, out, _ = at_the_keyboard("1\n2\n")
        self.assertEqual(code, 0)
        self.assertIn("./install.sh --check", out)
        self.assertIn("ROOT_SETUP_TOKEN", out)
        self.assertNotIn("What works today", out)
        self.assertEqual(out.count("8  Quit"), 3, "the menu should show again after each answer and once at the start")

    def test_quit_ends_it_and_so_does_the_end_of_the_input(self):
        code, out, _ = at_the_keyboard("8\n")
        self.assertEqual((code, "Bye." in out), (0, True))
        code, out, _ = at_the_keyboard("")
        self.assertEqual((code, "Bye." in out), (0, False), "ending the input is not the same as choosing Quit, but it must leave quietly")

    def test_a_wrong_choice_asks_again(self):
        code, out, _ = at_the_keyboard("9\nhello\n8\n")
        self.assertEqual(code, 0)
        self.assertEqual(out.count("Please type a number from 1 to 8."), 2)

    def test_status_logs_and_stop_work_from_the_menu_when_nothing_runs(self):
        code, out, _ = at_the_keyboard("4\n5\n6\n8\n")
        self.assertEqual(code, 0)
        self.assertEqual(out.count("MetaService is not running."), 2)
        self.assertIn("No log yet", out)

    def test_choosing_3_checks_first_and_returns_to_the_menu_when_the_settings_are_wrong(self):
        code, out, err = at_the_keyboard("3\n8\n", env_text="ROOT_SETUP_TOKEN=tiny\n")
        self.assertEqual(code, 0)
        self.assertIn("[1/3] Checking the settings", out)
        self.assertIn("ROOT_SETUP_TOKEN", err)
        self.assertNotIn("[2/3]", out)
        self.assertIn("Bye.", out)

    def test_choosing_7_turns_the_login_item_on_and_choosing_it_again_turns_it_off(self):
        code, out, _ = at_the_keyboard("7\n7\n8\n")
        self.assertEqual(code, 0)
        self.assertIn("currently off", out)
        self.assertIn("currently on", out)


class NamedCommandTest(unittest.TestCase):
    def test_the_commands_can_be_named_instead_of_chosen(self):
        for word, expected in (("help", "./install.sh --check"), ("readme", "ROOT_SETUP_TOKEN")):
            done = install("", word)
            self.assertEqual(done.returncode, 0, word)
            self.assertIn(expected, done.stdout, word)

    def test_a_named_install_with_a_bad_env_exits_one(self):
        done = install("ROOT_SETUP_TOKEN=tiny\n", "install")
        self.assertEqual(done.returncode, 1)
        self.assertIn("ROOT_SETUP_TOKEN", done.stderr)

    def test_status_and_stop_can_be_named(self):
        self.assertIn("not running", install("", "status").stdout)
        self.assertIn("not running", install("", "stop").stdout)

    def test_an_unknown_word_is_refused_with_the_help(self):
        done = install("", "banana")
        self.assertEqual(done.returncode, 1)
        self.assertIn("I do not know", done.stdout)
        self.assertIn("./install.sh help", done.stdout)


if __name__ == "__main__":
    unittest.main()
