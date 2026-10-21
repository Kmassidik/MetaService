import hashlib
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "build-linux-helpers.sh")

X86_FILE = "ELF 64-bit LSB executable, x86-64, statically linked"
ARM_FILE = "ELF 64-bit LSB executable, ARM aarch64, statically linked"
NAMES = ["metaservice-agent-linux-x86_64", "metaservice-agent-linux-arm64"]

# A pretend nix: `nix build .#metaservice-agent-<system> -o <link>` makes <link>/bin/metaservice-agent holding the system's name.
FAKE_NIX = """#!/bin/sh
system="${2#.#metaservice-agent-}"
mkdir -p "$4/bin"
echo "program for $system" > "$4/bin/metaservice-agent"
"""

# A pretend `file`: describes a program by the system named inside it. FAKE_ARM_DESCRIPTION replaces the ARM answer.
FAKE_FILE = """#!/bin/sh
case "$(cat "$2")" in
  *linux-x86_64*) echo "$2: %s" ;;
  *linux-arm64*) echo "$2: ${FAKE_ARM_DESCRIPTION:-%s}" ;;
esac
""" % (X86_FILE, ARM_FILE)


class BuildLinuxHelpersTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="ms-helpers-")
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.bin = os.path.join(self.folder, "bin")
        os.makedirs(self.bin)
        self.write_tool("nix", FAKE_NIX)
        self.write_tool("file", FAKE_FILE)
        self.target = os.path.join(self.folder, "agent-builds")

    def write_tool(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as file:
            file.write(body)
        os.chmod(path, 0o755)

    def run_script(self, *arguments, **extra_env):
        env = {**os.environ, "PATH": self.bin + os.pathsep + os.environ["PATH"], **extra_env}
        done = subprocess.run(["/bin/sh", SCRIPT, *arguments], capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL, timeout=60)
        return done.returncode, done.stdout + done.stderr

    def sha256(self, name):
        with open(os.path.join(self.target, name), "rb") as file:
            return hashlib.sha256(file.read()).hexdigest()

    def test_both_helpers_are_copied_under_the_exact_names_and_runnable(self):
        code, out = self.run_script(self.target)
        self.assertEqual(code, 0, out)
        for name in NAMES:
            path = os.path.join(self.target, name)
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o755, name)
        self.assertEqual(sorted(os.listdir(self.target)), sorted(NAMES + ["SHA256SUMS"]))

    def test_the_checksums_file_matches_the_files(self):
        self.run_script(self.target)
        with open(os.path.join(self.target, "SHA256SUMS")) as file:
            lines = file.read().splitlines()
        self.assertEqual(lines, [f"{self.sha256(name)}  {name}" for name in ["metaservice-agent-linux-x86_64", "metaservice-agent-linux-arm64"]])

    def test_it_prints_each_size_and_the_start_of_each_checksum(self):
        code, out = self.run_script(self.target)
        self.assertEqual(code, 0, out)
        for name in NAMES:
            size = os.path.getsize(os.path.join(self.target, name))
            self.assertIn(f"{name}  {size} bytes  sha256 {self.sha256(name)[:16]}", out)

    def test_a_program_for_the_wrong_architecture_is_refused(self):
        code, out = self.run_script(self.target, FAKE_ARM_DESCRIPTION="ELF 64-bit LSB executable, x86-64, statically linked")
        self.assertNotEqual(code, 0)
        self.assertIn("Refusing linux-arm64", out)
        self.assertFalse(os.path.exists(os.path.join(self.target, "metaservice-agent-linux-arm64")))
        self.assertFalse(os.path.exists(os.path.join(self.target, "SHA256SUMS")))

    def test_something_that_is_not_a_program_is_refused(self):
        code, out = self.run_script(self.target, FAKE_ARM_DESCRIPTION="ASCII text")
        self.assertNotEqual(code, 0)
        self.assertIn("Refusing linux-arm64", out)

    def test_it_reaches_no_other_computer(self):
        with open(SCRIPT) as file:
            code = "\n".join(line for line in file.read().splitlines() if not line.lstrip().startswith("#"))
        for word in ["ssh ", "scp ", "rsync", "sudo", "curl "]:
            self.assertNotIn(word, code)


if __name__ == "__main__":
    unittest.main()
