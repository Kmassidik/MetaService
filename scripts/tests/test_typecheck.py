import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "..", "bundles", "chat", "ui", "typecheck.sh")


def run_with(baseline, found):
    """Runs typecheck.sh in a throw-away folder with a pretend svelte-check that reports `found` errors."""
    folder = tempfile.mkdtemp(prefix="ms-typecheck-")
    try:
        shutil.copy(SCRIPT, os.path.join(folder, "typecheck.sh"))
        with open(os.path.join(folder, "typecheck.baseline"), "w") as file:
            file.write(f"{baseline}\n")
        with open(os.path.join(folder, "fake-check.sh"), "w") as file:
            file.write("".join(f'echo "1791774112173 ERROR \\"src/a{i}.js\\" 1:1 \\"pretend\\""\n' for i in range(found)) + 'echo "1791774112173 COMPLETED 1 FILES"\n')
        env = {**os.environ, "SVELTE_CHECK": f"sh {os.path.join(folder, 'fake-check.sh')}"}
        done = subprocess.run(["sh", os.path.join(folder, "typecheck.sh")], capture_output=True, text=True, env=env, timeout=60)
        return done.returncode, done.stdout
    finally:
        shutil.rmtree(folder, True)


class TypecheckTest(unittest.TestCase):
    def test_the_same_number_of_errors_as_the_baseline_passes(self):
        code, out = run_with(5, 5)
        self.assertEqual(code, 0)
        self.assertIn("5 type errors, the same as the baseline", out)

    def test_one_more_error_than_the_baseline_fails_and_says_by_how_many(self):
        code, out = run_with(5, 6)
        self.assertEqual(code, 1)
        self.assertIn("6 type errors, more than the baseline of 5", out)

    def test_fewer_errors_pass_and_tell_you_to_lower_the_baseline(self):
        code, out = run_with(5, 3)
        self.assertEqual(code, 0)
        self.assertIn("Lower typecheck.baseline to 3", out)

    def test_no_errors_at_all_passes(self):
        code, _ = run_with(0, 0)
        self.assertEqual(code, 0)

    def test_the_real_baseline_file_is_a_whole_number(self):
        path = os.path.join(os.path.dirname(SCRIPT), "typecheck.baseline")
        with open(path) as file:
            self.assertTrue(file.read().strip().isdigit())


if __name__ == "__main__":
    unittest.main()
