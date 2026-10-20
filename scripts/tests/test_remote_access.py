import io
import os
import stat
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "remote_access"))
sys.path.insert(0, HERE)

import cf_api  # noqa: E402
import cf_commands  # noqa: E402
import cf_connector  # noqa: E402
import cf_env  # noqa: E402
import cf_ingress  # noqa: E402
import cf_state  # noqa: E402
from fake_cloudflare import ACCOUNT, TOKEN, TUNNEL_TOKEN, ZONE, FakeServer  # noqa: E402

GOOD_ENV = f"CLOUDFLARE_API_TOKEN={TOKEN}\nCLOUDFLARE_ACCOUNT_ID={ACCOUNT}\nCLOUDFLARE_ZONE_ID={ZONE}\nPUBLIC_BASE_URL=https://meta.example.com\n"
HOST = "meta.example.com"
ORIGIN = "http://127.0.0.1:9100"
CNAME = "{}.cfargotunnel.com"


class FakeLaunchd:
    def __init__(self, world, fail_start=False):
        self.world, self.started, self.stopped, self.fail_start, self.loaded = world, [], 0, fail_start, False

    def start(self, plist_path):
        if self.fail_start:
            raise cf_connector.ConnectorError("launchd would not load the connector job.")
        self.started.append(plist_path)
        self.loaded = True
        for tunnel_id in self.world.tunnels:
            self.world.connected.add(tunnel_id)
        return "gui/501"

    def stop(self):
        self.stopped += 1
        self.loaded = False
        self.world.connected.clear()

    def is_loaded(self):
        return self.loaded


class Fixture:
    """A fake Cloudflare, a temp state folder, and a Tool wired to them. `said` collects everything the tool prints."""

    def __init__(self, test, host=HOST, probe=None, binary=True, fail_start=False):
        self.server = FakeServer()
        test.addCleanup(self.server.stop)
        self.world = self.server.world
        folder = tempfile.TemporaryDirectory()
        test.addCleanup(folder.cleanup)
        self.state_dir = os.path.join(folder.name, "state")
        self.agents_dir = os.path.join(folder.name, "agents")
        self.said = []
        self.probes = []
        self.launchd = FakeLaunchd(self.world, fail_start)
        values = cf_env.read_env(GOOD_ENV)
        self.settings = cf_env.settings_from(values, host=host)
        self.api = cf_api.CloudflareApi(self.settings.token, self.server.base)
        self.statuses = probe or {}

        def probe_fn(url):
            self.probes.append(url)
            return self.statuses.get(url, 200)

        finder = (lambda: "/opt/homebrew/bin/cloudflared") if binary else self._no_binary
        self.tool = cf_commands.Tool(self.settings, self.api, probe_fn, self.launchd, self.state_dir, self.agents_dir,
                                     find_binary=finder, say=self.said.append, sleep=lambda seconds: None)

    @staticmethod
    def _no_binary():
        raise cf_connector.ConnectorError("cloudflared is not installed on this Mac.")

    def output(self):
        return "\n".join(self.said)


class SettingsTest(unittest.TestCase):
    def test_a_good_env_gives_the_host_and_the_default_panel_address(self):
        settings = cf_env.settings_from(cf_env.read_env(GOOD_ENV))
        self.assertEqual((settings.host, settings.origin, settings.tunnel_name), (HOST, ORIGIN, "metaservice"))

    def test_the_root_port_decides_the_origin(self):
        settings = cf_env.settings_from(cf_env.read_env(GOOD_ENV + "ROOT_PORT=9300\n"))
        self.assertEqual(settings.origin, "http://127.0.0.1:9300")

    def test_missing_settings_are_named_but_never_shown(self):
        with self.assertRaises(cf_env.SettingsError) as raised:
            cf_env.settings_from(cf_env.read_env("PUBLIC_BASE_URL=https://meta.example.com\nCLOUDFLARE_API_TOKEN=abc\n"))
        self.assertIn("CLOUDFLARE_ACCOUNT_ID", str(raised.exception))
        self.assertNotIn("abc", str(raised.exception))

    def test_ids_must_look_like_cloudflare_ids(self):
        bad = GOOD_ENV.replace(ACCOUNT, "short")
        with self.assertRaises(cf_env.SettingsError) as raised:
            cf_env.settings_from(cf_env.read_env(bad))
        self.assertIn("CLOUDFLARE_ACCOUNT_ID", str(raised.exception))

    def test_the_public_url_must_be_plain_https_with_a_name(self):
        for bad in ("http://meta.example.com", "https://meta.example.com:8443", "https://meta.example.com/panel", "https://1.2.3.4", "meta.example.com"):
            with self.assertRaises(cf_env.SettingsError, msg=bad):
                cf_env.settings_from(cf_env.read_env(GOOD_ENV.replace("https://meta.example.com", bad)))

    def test_another_projects_tunnel_id_is_ignored_not_used(self):
        settings = cf_env.settings_from(cf_env.read_env(GOOD_ENV + f"CLOUDFLARE_TUNNEL_ID={'c' * 32}\n"))
        self.assertNotIn("c" * 32, repr(settings))
        self.assertFalse(hasattr(settings, "tunnel_id"))

    def test_the_token_and_ids_never_appear_in_a_repr(self):
        text = repr(cf_env.settings_from(cf_env.read_env(GOOD_ENV)))
        for secret in (TOKEN, ACCOUNT, ZONE):
            self.assertNotIn(secret, text)

    def test_an_env_readable_by_others_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, ".env")
            with open(path, "w") as file:
                file.write(GOOD_ENV)
            os.chmod(path, 0o644)
            with self.assertRaises(cf_env.SettingsError) as raised:
                cf_env.load_env(path)
            self.assertIn("chmod 600", str(raised.exception))
            os.chmod(path, 0o600)
            self.assertEqual(cf_env.load_env(path)["PUBLIC_BASE_URL"], "https://meta.example.com")

    def test_a_tunnel_name_is_checked(self):
        with self.assertRaises(cf_env.SettingsError):
            cf_env.settings_from(cf_env.read_env(GOOD_ENV), tunnel_name="bad name; rm")


class PartsTest(unittest.TestCase):
    def test_the_api_only_talks_to_cloudflare_or_a_local_test_server(self):
        cf_api.CloudflareApi("t", cf_api.PRODUCTION_BASE)
        cf_api.CloudflareApi("t", "http://127.0.0.1:5555")
        for base in ("https://evil.example.com/client/v4", "http://192.168.1.5:80", "http://127.0.0.1.evil.com:80"):
            with self.assertRaises(cf_api.CloudflareError, msg=base):
                cf_api.CloudflareApi("t", base)

    def test_a_cloudflare_error_that_repeats_the_token_is_scrubbed(self):
        fx = Fixture(self)
        fx.world.echo_token_in_errors = True
        fx.world.fail["GET cfd_tunnel"] = 403
        fx.tool.check()
        self.assertIn("forced failure", fx.output())
        self.assertNotIn(TOKEN, fx.output())
        self.assertIn("***", fx.output())

    def test_the_tunnel_carries_one_route_and_a_404_catch_all(self):
        config = cf_ingress.config_for(HOST, ORIGIN)
        self.assertEqual(config["config"]["ingress"], [{"hostname": HOST, "service": ORIGIN}, {"service": "http_status:404"}])
        self.assertTrue(cf_ingress.routes_only_to(config, HOST, ORIGIN))
        self.assertFalse(cf_ingress.routes_only_to(config, "other.example.com", ORIGIN))

    def test_the_connector_job_reads_its_token_from_a_file_and_names_no_token(self):
        text = cf_connector.plist_text("/opt/homebrew/bin/cloudflared", "/x/state/cloudflared.token", "/x/state/cloudflared.log")
        self.assertIn("<string>--token-file</string>", text)
        self.assertIn("<string>/x/state/cloudflared.token</string>", text)
        self.assertIn(cf_connector.LABEL, text)
        self.assertNotIn(TUNNEL_TOKEN, text)

    def test_a_missing_cloudflared_is_a_clear_error(self):
        with self.assertRaises(cf_connector.ConnectorError) as raised:
            cf_connector.find_binary(which=lambda name: None, exists=lambda path: False)
        self.assertIn("brew install cloudflared", str(raised.exception))

    def test_launchd_falls_back_from_the_screen_domain_to_the_user_domain(self):
        calls = []

        def run(command, **options):
            calls.append(command[1:])
            return type("R", (), {"returncode": 0 if "bootstrap" not in command or "user/501" in command else 1})()

        domain = cf_connector.Launchd(501, run=run).start("/p.plist")
        self.assertEqual(domain, "user/501")
        self.assertIn(["bootstrap", "gui/501", "/p.plist"], calls)


class CheckAndPlanTest(unittest.TestCase):
    def test_everything_ready_passes_and_changes_nothing(self):
        fx = Fixture(self)
        self.assertEqual(fx.tool.check(), 0)
        self.assertEqual(fx.world.writes(), [])
        self.assertIn("Ready", fx.output())

    def test_an_account_owned_token_is_accepted(self):
        fx = Fixture(self)
        fx.world.user_token = False
        self.assertEqual(fx.tool.check(), 0)

    def test_a_disabled_token_is_refused(self):
        fx = Fixture(self)
        fx.world.token_active = False
        self.assertEqual(fx.tool.check(), 1)
        self.assertIn("not active", fx.output())

    def test_a_host_outside_the_zone_is_refused(self):
        fx = Fixture(self, host="meta.other.org")
        self.assertEqual(fx.tool.check(), 1)
        self.assertIn("not inside the zone", fx.output())

    def test_a_tunnel_with_the_same_name_that_is_not_ours_is_refused(self):
        fx = Fixture(self)
        fx.world.tunnels["f" * 32] = {"id": "f" * 32, "name": "metaservice", "config_src": "cloudflare"}
        self.assertEqual(fx.tool.check(), 1)
        self.assertIn("already exists and is not this tool's", fx.output())

    def test_a_dns_record_we_did_not_make_is_never_taken_over(self):
        fx = Fixture(self)
        fx.world.dns.append({"id": "r1", "name": HOST, "type": "CNAME", "content": "other.example.net"})
        self.assertEqual(fx.tool.up(), 1)
        self.assertEqual(fx.world.tunnels, {})
        self.assertEqual(fx.world.dns[0]["content"], "other.example.net")

    def test_a_panel_that_is_not_running_is_refused_before_anything_is_made(self):
        fx = Fixture(self, probe={ORIGIN + "/": 0})
        self.assertEqual(fx.tool.up(), 1)
        self.assertEqual(fx.world.writes(), [])
        self.assertIn("Start MetaService first", fx.output())

    def test_a_missing_cloudflared_is_refused_before_anything_is_made(self):
        fx = Fixture(self, binary=False)
        self.assertEqual(fx.tool.up(), 1)
        self.assertEqual(fx.world.writes(), [])

    def test_a_token_without_tunnel_rights_says_what_it_needs(self):
        fx = Fixture(self)
        fx.world.fail["GET cfd_tunnel"] = 403
        self.assertEqual(fx.tool.check(), 1)
        self.assertIn("Cloudflare Tunnel: Edit", fx.output())

    def test_plan_describes_the_work_and_changes_nothing(self):
        fx = Fixture(self)
        self.assertEqual(fx.tool.plan(), 0)
        self.assertEqual(fx.world.writes(), [])
        self.assertIn("MAAS's is not touched", fx.output())


class UpAndDownTest(unittest.TestCase):
    def test_up_makes_its_own_tunnel_with_exactly_one_route_and_one_dns_record(self):
        fx = Fixture(self)
        self.assertEqual(fx.tool.up(), 0)
        tunnel = next(iter(fx.world.tunnels.values()))
        self.assertEqual((tunnel["name"], tunnel["config_src"]), ("metaservice", "cloudflare"))
        self.assertTrue(cf_ingress.routes_only_to(fx.world.configs[tunnel["id"]], HOST, ORIGIN))
        record = fx.world.dns[0]
        self.assertEqual((record["type"], record["name"], record["proxied"], record["content"]), ("CNAME", HOST, True, CNAME.format(tunnel["id"])))
        self.assertEqual(len(fx.world.tunnels), 1)
        self.assertEqual(len(fx.world.dns), 1)

    def test_the_tunnel_token_lives_only_in_an_owner_only_file(self):
        fx = Fixture(self)
        fx.tool.up()
        path = os.path.join(fx.state_dir, "cloudflared.token")
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        with open(path) as file:
            self.assertEqual(file.read(), TUNNEL_TOKEN)
        plist = os.path.join(fx.agents_dir, cf_connector.LABEL + ".plist")
        with open(plist) as file:
            self.assertNotIn(TUNNEL_TOKEN, file.read())
        self.assertEqual(fx.launchd.started, [plist])

    def test_the_state_file_is_owner_only_and_holds_no_secret(self):
        fx = Fixture(self)
        fx.tool.up()
        path = os.path.join(fx.state_dir, cf_state.STATE_NAME)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        with open(path) as file:
            text = file.read()
        for secret in (TOKEN, TUNNEL_TOKEN, ACCOUNT, ZONE):
            self.assertNotIn(secret, text)

    def test_nothing_the_tool_says_ever_contains_a_token(self):
        fx = Fixture(self)
        fx.world.fail["POST dns_records"] = 500
        fx.tool.up()
        fx2 = Fixture(self)
        fx2.tool.up()
        fx2.tool.status()
        fx2.tool.down()
        for text in (fx.output(), fx2.output()):
            for secret in (TOKEN, TUNNEL_TOKEN):
                self.assertNotIn(secret, text)

    def test_up_twice_makes_nothing_twice(self):
        fx = Fixture(self)
        fx.tool.up()
        self.assertEqual(fx.tool.up(), 0)
        self.assertEqual(len(fx.world.tunnels), 1)
        self.assertEqual(len(fx.world.dns), 1)

    def test_a_failure_half_way_undoes_exactly_what_was_made(self):
        fx = Fixture(self)
        fx.world.fail["POST dns_records"] = 500
        self.assertEqual(fx.tool.up(), 3)
        self.assertEqual(fx.world.tunnels, {})
        self.assertEqual(fx.world.dns, [])
        self.assertIsNone(cf_state.load(fx.state_dir))
        self.assertFalse(os.path.exists(os.path.join(fx.state_dir, "cloudflared.token")))

    def test_a_connector_that_will_not_start_undoes_everything(self):
        fx = Fixture(self, fail_start=True)
        self.assertEqual(fx.tool.up(), 3)
        self.assertEqual((fx.world.tunnels, fx.world.dns), ({}, []))

    def test_a_host_that_does_not_answer_yet_keeps_the_work_and_says_so(self):
        fx = Fixture(self, probe={f"https://{HOST}/": 0})
        self.assertEqual(fx.tool.up(), 2)
        self.assertEqual(len(fx.world.tunnels), 1)
        self.assertIn("does not answer yet", fx.output())

    def test_a_panel_that_says_no_is_still_reachable(self):
        fx = Fixture(self, probe={f"https://{HOST}/": 403})
        self.assertEqual(fx.tool.up(), 0)

    def test_cloudflares_own_error_pages_do_not_count_as_reached(self):
        fx = Fixture(self, probe={f"https://{HOST}/": 530})
        self.assertEqual(fx.tool.up(), 2)

    def test_down_removes_only_what_up_made(self):
        fx = Fixture(self)
        fx.world.tunnels["e" * 32] = {"id": "e" * 32, "name": "mac-mini-ruvio", "config_src": "cloudflare"}
        fx.world.dns.append({"id": "other", "name": "panel.example.com", "type": "CNAME", "content": "x"})
        fx.tool.up()
        self.assertEqual(fx.tool.down(), 0)
        self.assertEqual(list(fx.world.tunnels), ["e" * 32])
        self.assertEqual([r["name"] for r in fx.world.dns], ["panel.example.com"])
        self.assertIsNone(cf_state.load(fx.state_dir))
        self.assertFalse(os.path.exists(os.path.join(fx.agents_dir, cf_connector.LABEL + ".plist")))
        self.assertFalse(os.path.exists(os.path.join(fx.state_dir, "cloudflared.token")))
        self.assertEqual(fx.launchd.stopped >= 1, True)

    def test_down_leaves_a_dns_record_that_someone_else_now_owns(self):
        fx = Fixture(self)
        fx.tool.up()
        fx.world.dns[0]["id"] = "taken-over"
        fx.world.calls.clear()
        self.assertEqual(fx.tool.down(), 0)
        self.assertEqual(len(fx.world.dns), 1)
        self.assertFalse([call for call in fx.world.calls if call.startswith("DELETE") and "dns_records" in call])

    def test_down_with_nothing_made_does_nothing(self):
        fx = Fixture(self)
        self.assertEqual(fx.tool.down(), 0)
        self.assertEqual(fx.world.writes(), [])

    def test_a_failed_removal_stays_recorded_so_down_can_be_run_again(self):
        fx = Fixture(self)
        fx.tool.up()
        fx.world.fail["DELETE cfd_tunnel"] = 500
        self.assertEqual(fx.tool.down(), 1)
        self.assertIn("tunnel_id", cf_state.load(fx.state_dir))
        del fx.world.fail["DELETE cfd_tunnel"]
        self.assertEqual(fx.tool.down(), 0)
        self.assertEqual(fx.world.tunnels, {})

    def test_status_before_and_after(self):
        fx = Fixture(self)
        self.assertEqual(fx.tool.status(), 1)
        fx.tool.up()
        self.assertEqual(fx.tool.status(), 0)
        self.assertIn("1 connection", fx.output())

    def test_status_notices_a_tunnel_with_no_connection(self):
        fx = Fixture(self)
        fx.tool.up()
        fx.world.connected.clear()
        self.assertEqual(fx.tool.status(), 1)

    def test_a_throwaway_host_and_tunnel_name_work_beside_the_real_ones(self):
        real = Fixture(self)
        real.tool.up()
        throwaway = Fixture(self, host="meta-test.example.com")
        throwaway.settings = cf_env.settings_from(cf_env.read_env(GOOD_ENV), host="meta-test.example.com", tunnel_name="metaservice-test")
        throwaway.tool.s = throwaway.settings
        throwaway.world.tunnels.update(real.world.tunnels)
        throwaway.world.dns.extend(real.world.dns)
        self.assertEqual(throwaway.tool.up(), 0)
        self.assertEqual(sorted(t["name"] for t in throwaway.world.tunnels.values()), ["metaservice", "metaservice-test"])


if __name__ == "__main__":
    unittest.main()


class CommandLineTest(unittest.TestCase):
    """The real command line, against the fake Cloudflare, so the host comes from what was made and the token never appears."""

    def setUp(self):
        import importlib.util
        from unittest import mock
        harmless = mock.patch.dict(os.environ, {"METASERVICE_LAUNCHCTL": "/usr/bin/true", "METASERVICE_AGENTS_DIR": tempfile.mkdtemp(prefix="ms-agents-")})
        harmless.start()
        self.addCleanup(harmless.stop)
        spec = importlib.util.spec_from_file_location("remote_access_main", os.path.join(HERE, "..", "remote_access", "__main__.py"))
        self.main_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.main_module)

    def write_env(self, folder, text):
        path = os.path.join(folder, ".env")
        with open(path, "w") as file:
            file.write(text)
        os.chmod(path, 0o600)
        return path

    def test_down_still_works_after_public_base_url_was_emptied(self):
        fx = Fixture(self)
        fx.tool.up()
        with tempfile.TemporaryDirectory() as folder:
            env = self.write_env(folder, GOOD_ENV.replace("PUBLIC_BASE_URL=https://meta.example.com\n", "PUBLIC_BASE_URL=\n"))
            code = self.main_module.main(["down", "--env", env, "--state-dir", fx.state_dir, "--api-base", fx.server.base])
        self.assertEqual(code, 0)
        self.assertEqual((fx.world.tunnels, fx.world.dns), ({}, []))

    def test_a_bad_env_is_refused_with_a_sentence_and_no_value(self):
        with tempfile.TemporaryDirectory() as folder:
            env = self.write_env(folder, "CLOUDFLARE_API_TOKEN=SECRETVALUE\n")
            captured = io.StringIO()
            old, sys.stderr = sys.stderr, captured
            try:
                code = self.main_module.main(["check", "--env", env, "--state-dir", folder])
            finally:
                sys.stderr = old
        self.assertEqual(code, 1)
        self.assertIn("CLOUDFLARE_ACCOUNT_ID", captured.getvalue())
        self.assertNotIn("SECRETVALUE", captured.getvalue())
