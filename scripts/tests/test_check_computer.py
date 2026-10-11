import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import check_computer  # noqa: E402


def levels(system, machine, swift=True, container=True):
    return [level for level, _ in check_computer.assess(system, machine, swift, container)]


def text(system, machine, swift=True, container=True):
    return " ".join(line for _, line in check_computer.assess(system, machine, swift, container))


class CheckComputerTest(unittest.TestCase):
    def test_an_apple_silicon_mac_with_everything_passes_and_gets_the_macos_install(self):
        self.assertEqual(levels("Darwin", "arm64"), ["ok", "ok", "ok"])
        self.assertIn("macOS install", text("Darwin", "arm64"))

    def test_a_missing_container_tool_only_warns(self):
        self.assertEqual(levels("Darwin", "arm64", container=False), ["ok", "ok", "warn"])
        self.assertIn("cannot create VMs", text("Darwin", "arm64", container=False))

    def test_missing_swift_stops_the_install_and_says_how_to_get_it(self):
        self.assertIn("stop", levels("Darwin", "arm64", swift=False))
        self.assertIn("xcode-select --install", text("Darwin", "arm64", swift=False))

    def test_an_intel_mac_is_stopped(self):
        self.assertEqual(levels("Darwin", "x86_64"), ["stop"])
        self.assertIn("Apple Silicon", text("Darwin", "x86_64"))

    def test_windows_is_stopped_in_every_shell_it_can_report_from(self):
        for name in ("Windows", "MINGW64_NT-10.0-22631", "MSYS_NT-10.0", "CYGWIN_NT-10.0"):
            self.assertEqual(levels(name, "x86_64"), ["stop"], name)
            self.assertIn("Windows is not supported", text(name, "x86_64"))

    def test_linux_is_stopped_for_the_parent_and_pointed_at_adding_it_as_a_machine(self):
        for machine in ("x86_64", "aarch64"):
            self.assertEqual(levels("Linux", machine), ["stop"], machine)
        self.assertIn("add this Linux computer as a machine", text("Linux", "x86_64"))

    def test_an_unknown_system_is_stopped(self):
        self.assertEqual(levels("FreeBSD", "amd64"), ["stop"])


if __name__ == "__main__":
    unittest.main()
