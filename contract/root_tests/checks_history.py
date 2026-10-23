"""The optional monitor numbers and the history route GET /api/machines/{id}/stats/history: its guards, its shape, that the parent's sampler fills it from a helper
without asking for the process list and without passing the one-call-per-4-seconds limit, and that the parent keeps the new numbers within limits. Rules: docs/monitor-contract.md."""
import time

from agent.fake.stats import FakeStats
from contract import spec
from contract.root_tests.checks_monitor import MACHINE, REFRESH_SECONDS, STATS_PATH, machine_with_helper, read_stats
from contract.root_tests.support import Browser, expect, running

HISTORY_PATH = f"/api/machines/{MACHINE}/stats/history"
FAST_SAMPLING = "HISTORY_INTERVAL_SECONDS=1\n"
DEFAULT_INTERVAL_SECONDS = 10
MAX_POINTS = 360
WAIT_FOR_POINTS_SECONDS = 20
WATCH_SECONDS = 9
POLL_PAUSE_SECONDS = 0.5
LIAR_TEMPERATURE = 0.0
LIAR_PERCENT = 500.0


def read_history(operator, query=""):
    reply = operator.request("GET", f"{HISTORY_PATH}{query}")
    expect(reply.status == 200, f"history gave {reply.status}: {reply.raw[:200]!r}")
    problems = spec.problems("MachineStatsHistory", reply.body)
    expect(not problems, f"the history does not fit the contract: {problems[:3]}")
    return reply.body


def wait_for_points(operator, wanted):
    deadline = time.time() + WAIT_FOR_POINTS_SECONDS
    while time.time() < deadline:
        body = read_history(operator)
        if len(body["points"]) >= wanted:
            return body
        time.sleep(POLL_PAUSE_SECONDS)
    raise AssertionError(f"fewer than {wanted} history points after {WAIT_FOR_POINTS_SECONDS} s: {read_history(operator)}")


def check_the_history_route_needs_the_session_and_the_right_host_and_knows_its_machines():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            expect(Browser(root, auto_login=False).request("GET", HISTORY_PATH).status == 401, "no session must be 401")
            expect(operator.request("GET", HISTORY_PATH, headers={"Host": "evil.example"}).status == 403, "a foreign Host must be 403")
            expect(operator.request("GET", "/api/machines/nobody/stats/history").status == 404, "an unknown machine must be 404")
            expect(operator.request("GET", "/api/machines/BAD%20ID/stats/history").status == 404, "a malformed id must be 404")
            expect(operator.request("POST", HISTORY_PATH, {}).status in (403, 404, 405), "history is a read: POST must not work")
            expect(helper.stats.calls == 0, "reading the history must never call the helper")
        finally:
            helper.stop()


def check_a_machine_with_no_readings_yet_has_an_empty_history_of_the_right_shape():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            body = read_history(operator)
            expect(body == {"interval_seconds": DEFAULT_INTERVAL_SECONDS, "points": []}, f"empty history: {body}")
        finally:
            helper.stop()


def check_a_bad_points_value_is_a_plain_400_and_good_ones_are_accepted():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root)
        try:
            for bad in ("points=0", "points=361", "points=-1", "points=", "points=abc", "points=05", "points=+5", "points=5.0", "points=1&points=2"):
                reply = operator.request("GET", f"{HISTORY_PATH}?{bad}")
                expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"{bad} gave {reply.status}: {reply.raw[:120]!r}")
                expect(not spec.problems("Error", reply.body), f"{bad}: not the plain error shape: {reply.body}")
            for good in ("points=1", f"points={MAX_POINTS}", "points=42"):
                read_history(operator, f"?{good}")
        finally:
            helper.stop()


def check_the_parent_fills_the_history_by_itself_without_asking_for_the_process_list():
    with running(env_text=FAST_SAMPLING) as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(measuring_first=False))
        try:
            body = wait_for_points(operator, 2)
            times = [point["t"] for point in body["points"]]
            expect(times == sorted(times) and len(set(times)) == len(times), f"oldest first, no point twice: {times}")
            expect(body["interval_seconds"] == 1, f"the test run shortens the interval: {body['interval_seconds']}")
            last = body["points"][-1]
            expect(last["mem_total"] > 0 and last["cpu_percent"] is not None and last["load"] and len(last["load"]) == 3, f"a point has the numbers the charts draw: {last}")
            expect(last["disk_read"] >= 0 and last["disk_write"] >= 0 and last["processes_count"] > 0 and "cpu_breakdown" in last, f"the optional numbers arrive when the helper sends them: {last}")
            expect(helper.stats.calls_with_processes == 0 and helper.stats.calls_without_processes >= 2, "the sampler never asks for the process list")
            newest = read_history(operator, "?points=1")["points"]
            expect(newest == body["points"][-1:] or len(newest) == 1, f"points=1 gives the newest point: {newest}")
        finally:
            helper.stop()


def check_a_person_watching_and_the_sampler_together_stay_inside_one_helper_call_per_shared_reading():
    with running(env_text=FAST_SAMPLING) as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(measuring_first=False))
        try:
            started = time.time()
            while time.time() - started < WATCH_SECONDS:
                read_stats(operator)
                time.sleep(POLL_PAUSE_SECONDS)
            allowed = int(WATCH_SECONDS / REFRESH_SECONDS) + 2
            expect(helper.stats.calls <= allowed, f"{helper.stats.calls} helper calls in {WATCH_SECONDS} s (a person polling twice a second plus a sampler every second); at most {allowed}")
        finally:
            helper.stop()


def check_the_history_stays_readable_after_the_helper_stops_answering_and_never_gets_zeros():
    with running(env_text=FAST_SAMPLING) as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(measuring_first=False))
        wait_for_points(operator, 1)
        helper.stop()
        time.sleep(REFRESH_SECONDS + 2)
        kept = read_history(operator)
        expect(len(kept["points"]) >= 1, "the last readings stay readable")
        expect(all(point["cpu_percent"] > 0 or point["mem_total"] > 0 for point in kept["points"]), "no invented zero points for the time the helper was silent")
        time.sleep(REFRESH_SECONDS + 1)
        expect(len(read_history(operator)["points"]) == len(kept["points"]), "a helper that does not answer adds no points")


def check_an_older_helper_without_the_new_numbers_gives_a_reply_without_them():
    with running(env_text=FAST_SAMPLING) as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(measuring_first=False, extras="none"))
        try:
            stats = read_stats(operator).body["stats"]
            for key in ("physical_cores", "core_of", "clusters", "breakdown", "frequency_mhz", "temperature_celsius"):
                expect(key not in stats["cpu"], f"cpu.{key} must be left out when the helper does not say: {stats['cpu']}")
            expect("disk_io" not in stats and "process_count" not in stats and "errors_in_total" not in stats["network"], "no new keys at all")
            expect(all("threads" not in process for process in stats["processes"]), "no thread counts")
            point = wait_for_points(operator, 1)["points"][-1]
            expect(not {"disk_read", "disk_write", "net_drops", "processes_count", "cpu_breakdown"} & set(point), f"unknown numbers are left out of the point: {point}")
        finally:
            helper.stop()


def check_the_parent_passes_on_the_new_numbers_of_a_linux_style_and_a_mac_style_helper():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(cores=32, physical=16, measuring_first=False))
        try:
            cpu = read_stats(operator).body["stats"]["cpu"]
            expect(cpu["core_count"] == 32 and cpu["physical_cores"] == 16 and len(cpu["core_of"]) == 32, f"16 cores, 32 threads: {cpu.get('physical_cores')} {cpu.get('core_of')}")
            expect(set(cpu["breakdown"]) == {"user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal"}, f"Linux gives all eight states: {cpu['breakdown']}")
            expect(cpu["frequency_mhz"]["max"] > 0 and cpu["temperature_celsius"] > 0 and "clusters" not in cpu, "Linux has frequency and temperature and no clusters")
        finally:
            helper.stop()
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(cores=8, measuring_first=False, extras="mac"))
        try:
            stats = read_stats(operator).body["stats"]
            expect(set(stats["cpu"]["breakdown"]) == {"user", "system", "nice", "idle"}, f"a Mac gives four states: {stats['cpu']['breakdown']}")
            expect([cluster["name"] for cluster in stats["cpu"]["clusters"]] == ["Performance", "Efficiency"], f"clusters: {stats['cpu'].get('clusters')}")
            expect("frequency_mhz" not in stats["cpu"] and "temperature_celsius" not in stats["cpu"], "a Mac gives no frequency or temperature")
            expect("drops_out_total" not in stats["network"] and "drops_in_total" in stats["network"], "a Mac counts drops on the way in only")
        finally:
            helper.stop()


class LyingExtras(FakeStats):
    """A helper whose optional numbers break the limits."""

    def reading(self, with_processes=True):
        reading = super().reading(with_processes)
        reading["cpu"]["core_of"] = [0, 1, 99]
        reading["cpu"]["physical_cores"] = 5000
        reading["cpu"]["temperature_celsius"] = LIAR_TEMPERATURE
        reading["cpu"]["breakdown"] = {"user": LIAR_PERCENT, "idle": 50.0}
        reading["cpu"]["frequency_mhz"] = {"average": 0.0, "max": 0.0}
        reading["disk_io"] = {"read_bytes_per_second": -1.0, "write_bytes_per_second": 5.0}
        reading["process_count"] = 10 ** 12
        return reading


def check_the_parent_drops_new_numbers_that_break_the_limits_instead_of_showing_zeros():
    with running() as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, LyingExtras(cores=4, measuring_first=False))
        try:
            reply = read_stats(operator)
            stats = reply.body["stats"]
            expect(reply.status == 200 and stats is not None, "a lying extra must not turn the reading into an error")
            cpu = stats["cpu"]
            expect("core_of" not in cpu and "physical_cores" not in cpu, f"a wrong grouping is dropped: {cpu.get('core_of')} {cpu.get('physical_cores')}")
            expect("temperature_celsius" not in cpu and "frequency_mhz" not in cpu, "0 degrees and 0 MHz are not readings")
            expect(cpu["breakdown"] == {"idle": 50.0}, f"only the in-range state is kept: {cpu.get('breakdown')}")
            expect("disk_io" not in stats and "process_count" not in stats, "a negative speed and an absurd count are dropped")
        finally:
            helper.stop()


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
