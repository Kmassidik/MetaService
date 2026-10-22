"""GPUs in the monitor: the new optional per-GPU numbers pass through the parent and are bounded (dropped, never clamped), the hour of history carries a per-GPU
series (and none for a machine without a GPU), more than 8 GPUs are cut, hostile text stays text, and an unreadable number is never a 0.
Rules: docs/monitor-contract.md."""
from agent.fake import stats_gpu
from agent.fake.stats import FakeStats
from contract.root_tests.checks_history import FAST_SAMPLING, read_history, wait_for_points
from contract.root_tests.checks_monitor import machine_with_helper, read_stats
from contract.root_tests.support import Browser, expect, running

MAX_GPUS = 8
MAX_PROGRAMS = 8
NAME_LIMIT = 64
HISTORY_GPU_KEYS = {"index", "utilization_percent", "memory_used_bytes", "temperature_celsius", "power_watts"}
OPTIONAL_GPU_KEYS = ("vendor", "power_watts", "power_limit_watts", "fan_percent", "clock_mhz", "processes")
VENDORS = ["nvidia", "amd", "intel", "apple"]


def with_machine(kinds, body, env_text=None):
    with running(env_text=env_text) as root:
        operator = Browser(root)
        helper = machine_with_helper(operator, root, FakeStats(gpus=kinds, measuring_first=False))
        try:
            body(operator)
        finally:
            helper.stop()


def check_gpu_stats_the_new_fields_of_gpus_of_every_maker_pass_through():
    def look(operator):
        gpus = read_stats(operator).body["stats"]["gpus"]
        expect([gpu["vendor"] for gpu in gpus] == VENDORS, f"vendors: {[gpu.get('vendor') for gpu in gpus]}")
        nvidia, amd, intel, apple = gpus
        expect(all(nvidia[key] > 0 for key in ("power_watts", "power_limit_watts", "fan_percent", "clock_mhz")), f"nvidia: {nvidia}")
        expect(0 < len(nvidia["processes"]) <= MAX_PROGRAMS and all(p["memory_bytes"] > 0 for p in nvidia["processes"]), f"programs: {nvidia['processes']}")
        expect("processes" not in amd and amd["power_watts"] > 0, f"amd: {amd}")
        expect(intel["utilization_percent"] is None and intel["memory_used_bytes"] is None and intel["clock_mhz"] > 0, f"intel: {intel}")
        expect(not {"power_watts", "fan_percent", "clock_mhz", "processes"} & set(apple) and apple["temperature_celsius"] is None, f"a Mac gives only use and memory: {apple}")
        expect(apple["memory_used_bytes"] <= apple["memory_total_bytes"], f"apple memory: {apple}")

    with_machine(VENDORS, look)


def check_gpu_stats_out_of_range_numbers_are_dropped_not_clamped_and_hostile_text_stays_text():
    def look(operator):
        gpu = read_stats(operator).body["stats"]["gpus"][0]
        expect(gpu["utilization_percent"] is None, f"140 percent must be dropped, not clamped to 100: {gpu['utilization_percent']!r}")
        expect(gpu["memory_used_bytes"] is None and gpu["memory_total_bytes"] is None, f"-5 and 2^60 bytes are dropped: {gpu}")
        expect(gpu["temperature_celsius"] is None, f"900 degrees is a broken sensor: {gpu['temperature_celsius']!r}")
        for key in ("power_watts", "power_limit_watts", "fan_percent", "clock_mhz"):
            expect(key not in gpu, f"{key} is outside its range and must be left out, not clamped: {gpu.get(key)!r}")
        expect(gpu["vendor"] == "unknown", f"an unknown maker is named unknown, the helper's words are not passed on: {gpu['vendor']!r}")
        expect(gpu["name"].startswith(stats_gpu.HOSTILE_GPU_NAME) and len(gpu["name"]) == NAME_LIMIT, f"hostile text stays text, cut to {NAME_LIMIT}: {gpu['name']!r}")
        programs = gpu["processes"]
        expect(len(programs) == MAX_PROGRAMS and all(len(p["name"]) <= NAME_LIMIT and p["name"].startswith("<b>miner</b>") for p in programs), f"programs cut: {len(programs)}")
        expect(all(p["memory_bytes"] > 0 for p in programs), "a program with negative memory is dropped")

    with_machine([stats_gpu.KIND_HOSTILE], look)


def check_gpu_stats_more_than_eight_gpus_are_cut_to_eight():
    def look(operator):
        stats = read_stats(operator).body["stats"]
        expect(len(stats["gpus"]) == MAX_GPUS, f"{len(stats['gpus'])} gpus kept of {stats_gpu.MANY_COUNT} sent")

    with_machine([stats_gpu.KIND_MANY], look)


def check_gpu_stats_a_gpu_that_gives_no_number_has_nulls_never_zeros_and_no_series():
    def look(operator):
        gpu = read_stats(operator).body["stats"]["gpus"][0]
        expect(all(gpu[key] is None for key in ("utilization_percent", "memory_used_bytes", "memory_total_bytes", "temperature_celsius")), f"nulls, not zeros: {gpu}")
        expect(not any(key in gpu for key in OPTIONAL_GPU_KEYS[1:]), f"nothing invented: {gpu}")
        points = wait_for_points(operator, 2)["points"]
        expect(all("gpus" not in point for point in points), f"no number, no series: {points[-1]}")

    with_machine([stats_gpu.KIND_SILENT], look, FAST_SAMPLING)


def check_gpu_stats_the_history_carries_a_series_per_gpu_and_none_without_a_gpu():
    def look(operator):
        points = wait_for_points(operator, 2)["points"]
        for point in points:
            series = point["gpus"]
            expect([entry["index"] for entry in series] == [0, 1, 2], f"one entry per GPU that had a number, by index: {series}")
            expect(all(set(entry) <= HISTORY_GPU_KEYS for entry in series), f"only the series keys: {series}")
            expect("power_watts" in series[0] and "power_watts" not in series[2], "power only where the GPU gave it")
            expect("temperature_celsius" not in series[2] and "memory_used_bytes" in series[2], f"a Mac: use and memory only: {series[2]}")
        newest = read_history(operator, "?points=1")["points"]
        expect(len(newest) == 1 and newest[0]["gpus"], f"points=1 keeps the series: {newest}")

    with_machine(["nvidia", "amd", "apple"], look, FAST_SAMPLING)

    def none(operator):
        points = wait_for_points(operator, 2)["points"]
        expect(all("gpus" not in point for point in points), f"absent GPU means no series: {points[-1]}")

    with_machine([], none, FAST_SAMPLING)


def check_gpu_stats_hostile_numbers_leave_no_series_values():
    def look(operator):
        points = wait_for_points(operator, 2)["points"]
        expect(all("gpus" not in point for point in points), f"every number was out of range: nothing to draw, and no zeros: {points[-1].get('gpus')}")

    with_machine([stats_gpu.KIND_HOSTILE], look, FAST_SAMPLING)


def check_gpu_stats_a_machine_without_gpu_has_no_gpus_key_and_the_answer_stays_small():
    def look(operator):
        expect("gpus" not in read_stats(operator).body["stats"], "no GPU, no key")

    with_machine([], look)

    def full(operator):
        reply = read_stats(operator)
        expect(len(reply.raw) < 64 * 1024, f"eight busy GPUs still fit the answer limit: {len(reply.raw)} bytes")

    with_machine(["nvidia"] * MAX_GPUS, full)


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
