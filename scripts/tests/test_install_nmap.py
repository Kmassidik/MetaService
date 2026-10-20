import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "install-nmap.sh")
CHECK = os.path.join(HERE, "..", "check_computer.py")


class FakeBrew:
    """A pretend Homebrew and a pretend place for nmap, in a throw-away folder. Nothing real is ever installed."""

    def __init__(self, test, works=True, makes_nmap=True):
        self.folder = tempfile.mkdtemp(prefix="ms-nmap-")
        test.addCleanup(shutil.rmtree, self.folder, True)
        self.nmap = os.path.join(self.folder, "bin", "nmap")
        os.makedirs(os.path.dirname(self.nmap))
        self.log = os.path.join(self.folder, "brew.log")
        self.brew = os.path.join(self.folder, "brew")
        body = f'#!/bin/sh\necho "brew $*" >> "{self.log}"\necho "no-auto-update=$HOMEBREW_NO_AUTO_UPDATE no-upgrade=$HOMEBREW_NO_INSTALL_UPGRADE" >> "{self.log}"\n'
        body += "exit 1\n" if not works else (f'cp /usr/bin/true "{self.nmap}"\n' if makes_nmap else "exit 0\n")
        with open(self.brew, "w") as file:
            file.write(body)
        os.chmod(self.brew, 0o755)
        self.env = {**os.environ, "METASERVICE_NMAP_PATHS": self.nmap, "METASERVICE_BREW": self.brew}

    def run(self, *arguments, env=None):
        done = subprocess.run(["/bin/sh", SCRIPT, *arguments], capture_output=True, text=True, env=env or self.env, stdin=subprocess.DEVNULL, timeout=60)
        return done.returncode, done.stdout + done.stderr

    def calls(self):
        return open(self.log).read().splitlines() if os.path.exists(self.log) else []


class InstallNmapTest(unittest.TestCase):
    def test_an_installed_nmap_is_left_alone(self):
        fake = FakeBrew(self)
        shutil.copy("/usr/bin/true", fake.nmap)
        code, out = fake.run()
        self.assertEqual(code, 0)
        self.assertIn("nmap is installed", out)
        self.assertEqual(fake.calls(), [])

    def test_a_missing_nmap_is_installed_alone_with_updates_switched_off(self):
        fake = FakeBrew(self)
        code, out = fake.run()
        self.assertEqual(code, 0, out)
        self.assertIn("nmap is installed", out)
        self.assertEqual(fake.calls()[0], "brew install nmap")
        self.assertIn("no-auto-update=1 no-upgrade=1", fake.calls()[1])
        self.assertEqual(len(fake.calls()), 2, "Homebrew was asked for anything besides installing nmap")
        self.assertTrue(os.access(fake.nmap, os.X_OK))

    def test_it_never_asks_for_a_password(self):
        fake = FakeBrew(self)
        with open(SCRIPT) as file:
            text = file.read()
        self.assertNotIn("sudo", "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#")))
        self.assertNotIn("brew update", "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#")))
        self.assertNotIn("brew upgrade", "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#")))
        self.assertEqual(fake.run()[0], 0)

    def test_a_failed_install_warns_and_goes_on(self):
        fake = FakeBrew(self, works=False)
        code, out = fake.run()
        self.assertEqual(code, 0)
        self.assertIn("could not install nmap", out)
        self.assertIn("fewer computers", out)

    def test_an_install_that_leaves_nmap_somewhere_unexpected_warns_and_goes_on(self):
        fake = FakeBrew(self, makes_nmap=False)
        code, out = fake.run()
        self.assertEqual(code, 0)
        self.assertIn("not where MetaService looks", out)

    def test_without_homebrew_it_warns_and_goes_on(self):
        fake = FakeBrew(self)
        env = {**fake.env, "METASERVICE_BREW": os.path.join(fake.folder, "no-brew-here"), "PATH": "/usr/bin:/bin"}
        code, out = fake.run(env=env)
        self.assertEqual(code, 0)
        self.assertIn("Homebrew is not here", out)
        self.assertEqual(fake.calls(), [])

    def test_no_install_leaves_it_out_and_says_what_that_costs(self):
        fake = FakeBrew(self)
        code, out = fake.run("--no-install")
        self.assertEqual(code, 0)
        self.assertIn("you chose to go without it", out)
        self.assertIn("add a computer by its address", out)
        self.assertEqual(fake.calls(), [])

    def test_no_install_still_accepts_an_nmap_that_is_there(self):
        fake = FakeBrew(self)
        shutil.copy("/usr/bin/true", fake.nmap)
        code, out = fake.run("--no-install")
        self.assertIn("nmap is installed", out)
        self.assertEqual(code, 0)


class ComputerCheckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import importlib.util
        spec = importlib.util.spec_from_file_location("check_computer_for_nmap", CHECK)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def levels(self, **extra):
        return [level for level, _ in self.module.assess("Darwin", "arm64", True, True, **extra)]

    def text(self, **extra):
        return " ".join(line for _, line in self.module.assess("Darwin", "arm64", True, True, **extra))

    def test_nmap_is_only_reported_when_the_caller_says_whether_it_is_there(self):
        self.assertEqual(self.levels(), ["ok", "ok", "ok"])

    def test_a_missing_nmap_only_warns_and_says_the_install_adds_it(self):
        self.assertEqual(self.levels(nmap_found=False), ["ok", "ok", "ok", "warn"])
        self.assertIn("The install adds it for you with Homebrew", self.text(nmap_found=False))
        self.assertIn("--skip-nmap", self.text(nmap_found=False))

    def test_a_found_nmap_is_ok(self):
        self.assertEqual(self.levels(nmap_found=True), ["ok", "ok", "ok", "ok"])


if __name__ == "__main__":
    unittest.main()
