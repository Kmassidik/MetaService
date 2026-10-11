import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import check_env  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "check_env.py")
GOOD_TOKEN = "a" * check_env.MIN_TOKEN_LENGTH


def problems(text, mode=0o600):
    return check_env.problems_in(check_env.read_env(text), mode)


class CheckEnvTest(unittest.TestCase):
    def test_an_empty_example_file_is_fine(self):
        self.assertEqual(problems("# comment\nROOT_SETUP_TOKEN=\nAI_API_KEY=\nROOT_PORT=\n"), [])

    def test_a_token_one_character_short_is_refused_and_the_exact_length_passes(self):
        self.assertEqual(len(problems("ROOT_SETUP_TOKEN=" + GOOD_TOKEN[:-1])), 1)
        self.assertEqual(problems("ROOT_SETUP_TOKEN=" + GOOD_TOKEN), [])

    def test_a_quoted_token_counts_without_its_quotes(self):
        self.assertEqual(len(problems('ROOT_SETUP_TOKEN="' + GOOD_TOKEN[:-1] + '"')), 1)
        self.assertEqual(problems('ROOT_SETUP_TOKEN="' + GOOD_TOKEN + '"'), [])

    def test_the_value_is_never_printed(self):
        secret = "short-secret"
        self.assertNotIn(secret, " ".join(problems("ROOT_SETUP_TOKEN=" + secret + "\nROOT_PORT=" + secret)))

    def test_bad_ports_are_refused(self):
        for bad in ("0", "65536", "ninety", "-1", "9100x"):
            self.assertEqual(len(problems("ROOT_AGENT_PORT=" + bad)), 1, bad)
        for good in ("1", "9102", "65535"):
            self.assertEqual(problems("ROOT_PORT=" + good), [], good)

    def test_half_filled_ai_settings_are_refused_and_all_or_none_pass(self):
        self.assertIn("AI_API_KEY", problems("AI_BASE_URL=https://x\nAI_DEFAULT_MODEL=m")[0])
        self.assertEqual(len(problems("AI_API_KEY=k")), 1)
        self.assertEqual(problems("AI_BASE_URL=https://x\nAI_API_KEY=k\nAI_DEFAULT_MODEL=m"), [])

    def test_a_file_other_users_can_read_is_refused(self):
        self.assertEqual(len(problems("", mode=0o644)), 1)
        self.assertEqual(len(problems("", mode=0o640)), 1)
        self.assertEqual(problems("", mode=0o600), [])

    def test_all_problems_are_listed_at_once(self):
        self.assertEqual(len(problems("ROOT_SETUP_TOKEN=x\nROOT_PORT=0\nAI_API_KEY=k", mode=0o644)), 4)


class CheckEnvCommandTest(unittest.TestCase):
    def run_on(self, text, mode=0o600):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, ".env")
            with open(path, "w") as file:
                file.write(text)
            os.chmod(path, mode)
            return subprocess.run([sys.executable, SCRIPT, path], capture_output=True, text=True)

    def test_a_good_file_exits_zero_and_says_nothing(self):
        done = self.run_on("ROOT_SETUP_TOKEN=" + GOOD_TOKEN)
        self.assertEqual((done.returncode, done.stdout, done.stderr), (0, "", ""))

    def test_a_bad_file_exits_one_and_names_the_setting_but_not_its_value(self):
        done = self.run_on("ROOT_SETUP_TOKEN=tiny")
        self.assertEqual(done.returncode, 1)
        self.assertIn("ROOT_SETUP_TOKEN", done.stderr)
        self.assertNotIn("tiny", done.stderr.replace("ROOT_SETUP_TOKEN", ""))

    def test_a_missing_file_is_fine(self):
        done = subprocess.run([sys.executable, SCRIPT, "/nonexistent/.env"], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0)


if __name__ == "__main__":
    unittest.main()
