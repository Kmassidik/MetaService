"""The monitor route GET /api/machines/{id}/stats: who may read it, the envelope, the shared reading (one helper call per ~4 s), the limits the parent applies again,
offline and old-helper machines, and the same route through a real helper behind the SSH tunnel. Rules: docs/monitor-contract.md."""
import copy
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from agent.fake.engine import FakeEngine
from agent.fake.server import make_server
from agent.fake.stats import HOSTILE_NAME, SECRET_COMMAND_LINE, FakeStats
from contract import spec
from contract.root_tests.checks_terminal import console_world
from contract.root_tests.support import Browser, expect, good_heartbeat, running

MACHINE = "mini"
REMOTE_MACHINE = "test-box"
STATS_PATH = f"/api/machines/{MACHINE}/stats"
REFRESH_SECONDS = 4
IDLE_DROP_SECONDS = 30
SETTLE_SECONDS = 0.3
CONCURRENT_ASKERS = 20
MAX_PROCESSES = 15
NAME_LIMIT = 64
CORE_LIMIT = 1024
LIAR_CORES = 3000
LIAR_PROCESSES = 40
LIAR_NAME = "N" * 500


class LyingStats(FakeStats):
    """A helper that ignores the contract: too many cores and processes, huge names, a percentage over 100."""

    def reading(self, with_processes=True):
        reading = super().reading(with_processes)
        reading["cpu"]["core_count"] = LIAR_CORES
        reading["cpu"]["cores_percent"] = [250.0] * LIAR_CORES
        template = reading["processes"][0]
        reading["processes"] = [{**template, "pid": 1000 + n, "name": LIAR_NAME, "user": LIAR_NAME} for n in range(LIAR_PROCESSES)]
        return reading


class HelperThread:
    """A fake helper on loopback, served from a thread of this test so the test can count its calls and stop it."""

    def __init__(self, token, stats):
        self.stats = stats
        self.server = make_server(FakeEngine(), token, "127.0.0.1", 0, stats)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


class NoStatsHelper:
    """An older helper: every path except health is 404."""

    def __init__(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(404)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"error":{"code":"not_found","message":"no such path"}}')

            def log_message(self, *args):
                return

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


def enroll(operator, name=MACHINE):
    invite = operator.write("POST", "/api/enrollments", {"name": name})
    expect(invite.status == 201, f"invite gave {invite.status}")
    reply = Browser(operator.root).request("POST", "/v1/agents/enroll", {"enrollment_token": invite.body["enrollment_token"], "name": name}, origin=None)
    expect(reply.status == 200, f"enroll gave {reply.status}")
    return reply.body["machine_token"], reply.body["command_token"]


def beat(root, machine_token, helper_port):
    body = copy.deepcopy(good_heartbeat())
    body["agent_port"] = helper_port
    reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {machine_token}"}, origin=None)
    expect(reply.status == 204, f"heartbeat gave {reply.status}: {reply.raw[:150]!r}")


def machine_with_helper(operator, root, stats=None):
    machine_token, command_token = enroll(operator)
    helper = HelperThread(command_token, stats or FakeStats())
    beat(root, machine_token, helper.port)
    return helper


def read_stats(operator):
    reply = operator.request("GET", STATS_PATH)
    expect(reply.status == 200, f"stats gave {reply.status}: {reply.raw[:200]!r}")
    problems = spec.problems("MachineStatsReply", reply.body)
    expect(not problems, f"the reply does not fit the contract: {problems[:3]}")
    return reply


def check_the_stats_route_needs_the_session_and_the_right_host_and_knows_its_machines():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            expect(Browser(root, auto_login=False).request("GET", STATS_PATH).status == 401, "no session must be 401")
            expect(operator.request("GET", STATS_PATH, headers={"Host": "evil.example"}).status == 403, "a foreign Host must be 403")
            expect(operator.request("GET", "/api/machines/nobody/stats").status == 404, "an unknown machine must be 404")
            expect(operator.request("GET", "/api/machines/BAD%20ID/stats").status == 404, "a malformed id must be 404")
            expect(operator.request("POST", STATS_PATH, {}).status in (403, 404, 405), "stats is a read: POST must not work")
            expect(helper.stats.calls == 0, "a refused request must not reach the helper")
        finally:
            helper.stop()


def check_the_helper_is_asked_once_per_four_seconds_however_many_ask():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            first = read_stats(operator)
            expect(first.body["state"] == "online" and first.body["stats"]["measuring"] is True, "the first reading says measuring")
            expect(first.body["stats"]["cpu"]["total_percent"] is None, "measuring means null, never 0")
            for _ in range(5):
                read_stats(operator)
            expect(helper.stats.calls == 1, f"six reads inside {REFRESH_SECONDS} s must make 1 helper call, made {helper.stats.calls}")
            time.sleep(REFRESH_SECONDS + SETTLE_SECONDS)
            later = read_stats(operator)
            expect(helper.stats.calls == 2, f"after {REFRESH_SECONDS} s the helper is asked again: {helper.stats.calls}")
            expect(later.body["stats"]["measuring"] is False and later.body["stats"]["cpu"]["total_percent"] is not None, "the second reading has numbers")
        finally:
            helper.stop()


def check_twenty_tabs_asking_at_once_share_one_helper_call():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        operator.sign_in()
        try:
            def ask(_):
                return Browser(root, auto_login=False).request("GET", STATS_PATH, cookies=False, headers={"Cookie": "; ".join(f"{k}={v}" for k, v in operator.cookies.items())}).status

            with ThreadPoolExecutor(max_workers=CONCURRENT_ASKERS) as pool:
                statuses = list(pool.map(ask, range(CONCURRENT_ASKERS)))
            expect(statuses == [200] * CONCURRENT_ASKERS, f"statuses: {statuses}")
            expect(helper.stats.calls == 1, f"{CONCURRENT_ASKERS} askers at once must share one call, made {helper.stats.calls}")
        finally:
            helper.stop()


def read_without_processes(operator):
    reply = operator.request("GET", f"{STATS_PATH}?processes=0")
    expect(reply.status == 200, f"stats?processes=0 gave {reply.status}: {reply.raw[:200]!r}")
    problems = spec.problems("MachineStatsReply", reply.body)
    expect(not problems, f"the reply does not fit the contract: {problems[:3]}")
    return reply


def check_processes_zero_gives_an_empty_list_and_asks_the_helper_not_to_scan():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            reply = read_without_processes(operator)
            expect(reply.body["state"] == "online" and reply.body["stats"]["processes"] == [], f"no list wanted, none sent: {reply.body['stats']['processes']}")
            expect(helper.stats.calls_without_processes == 1 and helper.stats.calls_with_processes == 0, "the helper was asked to skip the scan")
            expect(helper.stats.queries == ["processes=0"], f"only the fixed query goes to the helper: {helper.stats.queries}")
        finally:
            helper.stop()


def check_without_the_parameter_or_with_one_the_list_comes_as_before():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            plain = read_stats(operator).body["stats"]
            expect(len(plain["processes"]) == MAX_PROCESSES, f"today's behaviour: {len(plain['processes'])} processes")
            explicit = operator.request("GET", f"{STATS_PATH}?processes=1")
            expect(explicit.status == 200 and len(explicit.body["stats"]["processes"]) == MAX_PROCESSES, "processes=1 is the same as nothing")
            expect(helper.stats.calls == 1 and helper.stats.queries == [""], f"one shared call with no query: {helper.stats.queries}")
        finally:
            helper.stop()


def check_a_reading_with_processes_also_answers_a_request_without_them():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            read_stats(operator)
            lean = read_without_processes(operator)
            expect(lean.body["stats"]["processes"] == [], "the list is dropped for the asker who did not want it")
            expect(helper.stats.calls == 1, f"the held reading is enough: {helper.stats.calls} helper calls")
        finally:
            helper.stop()


def check_a_request_with_processes_after_one_without_asks_the_helper_again_once():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            read_without_processes(operator)
            full = read_stats(operator)
            expect(len(full.body["stats"]["processes"]) == MAX_PROCESSES, "the list is there once it was asked for")
            expect(helper.stats.calls == 2, f"one more helper call for the list: {helper.stats.calls}")
            read_stats(operator)
            read_without_processes(operator)
            expect(helper.stats.calls == 2, f"after that, both kinds are served from the held reading inside {REFRESH_SECONDS} s: {helper.stats.calls}")
        finally:
            helper.stop()


def check_twenty_mixed_askers_cost_at_most_two_helper_calls():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        operator.sign_in()
        cookie = "; ".join(f"{k}={v}" for k, v in operator.cookies.items())
        try:
            def ask(n):
                suffix = "?processes=0" if n % 2 else ""
                return Browser(root, auto_login=False).request("GET", STATS_PATH + suffix, cookies=False, headers={"Cookie": cookie}).status

            with ThreadPoolExecutor(max_workers=CONCURRENT_ASKERS) as pool:
                statuses = list(pool.map(ask, range(CONCURRENT_ASKERS)))
            expect(statuses == [200] * CONCURRENT_ASKERS, f"statuses: {statuses}")
            expect(helper.stats.calls <= 2, f"mixed askers at once must make at most 2 helper calls, made {helper.stats.calls}")
        finally:
            helper.stop()


def check_an_unknown_value_of_processes_is_a_400_in_the_plain_shape_and_never_reaches_the_helper():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            for bad in ("processes=2", "processes=", "processes=true", "processes=0;x", "processes=%32", "processes=1&processes=0", "processes=a/b"):
                reply = operator.request("GET", f"{STATS_PATH}?{bad}")
                expect(reply.status == 400, f"{bad} must be 400, got {reply.status}")
                problems = spec.problems("Error", reply.body)
                expect(not problems and reply.body["error"]["code"] == "invalid_input", f"{bad}: {reply.body}")
            expect(helper.stats.calls == 0, "a refused request must not reach the helper")
            expect(operator.request("GET", f"{STATS_PATH}?other=1").status == 200, "another parameter is ignored")
            expect(helper.stats.queries == [""], f"nothing the caller typed is passed on: {helper.stats.queries}")
        finally:
            helper.stop()


def check_a_hostile_process_name_stays_text_and_a_command_line_never_arrives():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            reply = read_stats(operator)
            names = [process["name"] for process in reply.body["stats"]["processes"]]
            expect(HOSTILE_NAME in names, f"the hostile name must arrive unchanged as text: {names}")
            expect(SECRET_COMMAND_LINE.encode() not in reply.raw and b"SECRET-FAKE" not in reply.raw, "a command line reached the panel")
            expect(reply.header("content-type") == "application/json", f"content type: {reply.header('content-type')}")
            expect(reply.header("x-content-type-options") == "nosniff", "nosniff is missing")
        finally:
            helper.stop()


def check_the_parent_applies_the_limits_again_to_a_helper_that_lies():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, LyingStats())
        try:
            stats = read_stats(operator).body["stats"]
            expect(len(stats["processes"]) == MAX_PROCESSES, f"processes: {len(stats['processes'])}")
            expect(all(len(p["name"]) <= NAME_LIMIT and len(p["user"]) <= NAME_LIMIT for p in stats["processes"]), "a name was not cut")
            expect(len(stats["cpu"]["cores_percent"]) == CORE_LIMIT and stats["cpu"]["core_count"] <= CORE_LIMIT, "cores were not limited")
            expect(max(stats["cpu"]["cores_percent"]) <= 100, "a percentage passed 100")
        finally:
            helper.stop()


def check_gpu_block_is_left_out_without_a_gpu_and_kept_with_one():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(gpu=True))
        try:
            stats = read_stats(operator).body["stats"]
            expect(stats.get("gpus") and stats["gpus"][0]["name"].startswith("NVIDIA"), f"gpus: {stats.get('gpus')}")
        finally:
            helper.stop()
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            expect("gpus" not in read_stats(operator).body["stats"], "no GPU: the key must be left out, not zeros")
        finally:
            helper.stop()


def check_a_machine_that_never_reported_is_offline_with_null_stats():
    with running() as root:
        operator = Browser(root)
        enroll(operator)
        body = read_stats(operator).body
        expect(body["state"] == "offline" and body["stats"] is None and body["last_seen"] is None and body["fetched_at"] is None, f"never reported: {body}")


def check_an_older_helper_without_the_route_is_named_not_zeroed():
    with running() as root:
        operator = Browser(root)
        machine_token, _ = enroll(operator)
        helper = NoStatsHelper()
        try:
            beat(root, machine_token, helper.port)
            body = read_stats(operator).body
            expect(body["state"] == "old_helper" and body["stats"] is None and body["last_seen"], f"older helper: {body}")
        finally:
            helper.stop()


def check_a_helper_that_goes_away_leaves_offline_with_the_last_numbers_until_thirty_idle_seconds():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        read_stats(operator)
        helper.stop()
        time.sleep(REFRESH_SECONDS + SETTLE_SECONDS)
        gone = read_stats(operator).body
        expect(gone["state"] == "offline" and gone["stats"] is not None and gone["fetched_at"], f"the last numbers must stay for the greyed view: {gone}")
        expect(gone["stats"]["memory"]["total_bytes"] > 0, "the greyed numbers are the real last ones")
        time.sleep(IDLE_DROP_SECONDS + 1)
        dropped = read_stats(operator).body
        expect(dropped["state"] == "offline" and dropped["stats"] is None, f"nobody asked for {IDLE_DROP_SECONDS} s: the reading is dropped: {dropped}")


def check_a_real_helper_behind_the_ssh_tunnel_answers_the_monitor_route():
    with console_world(vm_count=0) as (root, operator, _):
        reply = operator.request("GET", f"/api/machines/{REMOTE_MACHINE}/stats")
        expect(reply.status == 200, f"stats gave {reply.status}: {reply.raw[:200]!r}")
        problems = spec.problems("MachineStatsReply", reply.body)
        expect(not problems, f"the reply does not fit the contract: {problems[:3]}")
        expect(reply.body["state"] == "online" and reply.body["stats"]["cpu"]["core_count"] >= 1, f"real helper: {json.dumps(reply.body)[:300]}")
        expect(len(reply.body["stats"]["processes"]) <= MAX_PROCESSES and "gpus" not in reply.body["stats"], "a Mac has at most 15 processes and no gpus block")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
