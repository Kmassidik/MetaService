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



ROUTE = "   route to: default\n    gateway: 192.168.0.1\n  interface: en0\n"


def ifconfig(address, mask):
    return f"en0: flags=8863<UP>\n\tinet {address} netmask {mask} broadcast 192.168.0.255\n\tstatus: active\n"


class NetworkCheckTest(unittest.TestCase):
    def test_a_home_or_office_network_is_named_with_the_address_and_interface(self):
        level, line = check_computer.describe_network(ROUTE, ifconfig("192.168.0.40", "0xffffff00"))
        self.assertEqual(level, "ok")
        self.assertIn("192.168.0.0/24", line)
        self.assertIn("192.168.0.40 on en0", line)

    def test_a_public_address_warns_and_points_at_scan_subnet(self):
        level, line = check_computer.describe_network(ROUTE, ifconfig("202.72.223.27", "0xfffffff0"))
        self.assertEqual(level, "warn")
        self.assertIn("public", line)
        self.assertIn("SCAN_SUBNET", line)

    def test_a_network_wider_than_a_slash_22_warns_because_the_scan_would_refuse_it(self):
        level, line = check_computer.describe_network(ROUTE, ifconfig("10.1.2.3", "0xffff0000"))
        self.assertEqual(level, "warn")
        self.assertIn("10.1.0.0/16", line)
        self.assertIn("too big", line)

    def test_a_slash_22_is_the_widest_that_still_passes(self):
        self.assertEqual(check_computer.describe_network(ROUTE, ifconfig("10.1.2.3", "0xfffffc00"))[0], "ok")

    def test_no_route_or_no_address_warns_and_never_fails_the_install(self):
        self.assertEqual(check_computer.describe_network("", "")[0], "warn")
        self.assertEqual(check_computer.describe_network(ROUTE, "en0: flags=8863<UP>\n")[0], "warn")


if __name__ == "__main__":
    unittest.main()
