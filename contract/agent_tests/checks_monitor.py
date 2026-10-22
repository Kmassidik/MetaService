"""The helper's monitor route: GET /v1/stats. Runs against the real macOS helper (simulated engine), the Linux helper (where /proc exists), or with
`python -m contract.agent_tests.runner --fake` against the Fake Agent. Rules: docs/monitor-contract.md."""
import os
import subprocess
import sys
import time

from contract import spec
from contract.agent_tests.checks_terminal import helper
from contract.root_tests.support import expect

STATS = "/v1/stats"
SECRET_ARGUMENT = "SECRET-ARGV-VALUE-0451"
MAX_PROCESSES = 15
NAME_LIMIT = 64
SAMPLE_GAP_SECONDS = 1.2
BREAKDOWN_STATES = {"user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal"}
MAC_BREAKDOWN_STATES = {"user", "system", "nice", "idle"}
ROUNDING_ALLOWANCE = 1.0
FULL_SHARE = 100.0


def fetch(one):
    status, body = one.call("GET", STATS)
    expect(status == 200, f"stats gave {status}: {body}")
    problems = spec.problems("Stats", body)
    expect(not problems, f"the answer does not fit the contract: {problems[:3]}")
    return body


def check_stats_needs_the_command_token():
    with helper() as one:
        expect(one.call("GET", STATS, token=None)[0] == 401, "no token must be 401")
        expect(one.call("GET", STATS, token="wrong-" + one.token)[0] == 401, "a wrong token must be 401")


def check_stats_is_read_only():
    with helper() as one:
        for method in ("POST", "DELETE"):
            status = one.call(method, STATS, {} if method != "DELETE" else None)[0]
            expect(status in (404, 405), f"{method} {STATS} gave {status}: the monitor can only look")


def check_the_first_answer_says_measuring_with_nulls_and_the_second_has_numbers():
    with helper() as one:
        first = fetch(one)
        expect(first["measuring"] is True, "the first answer after start must say measuring")
        expect(first["cpu"]["total_percent"] is None and first["cpu"]["cores_percent"] is None, "measuring means null, never 0")
        expect(first["network"]["received_bytes_per_second"] is None, "network speed is null while measuring")
        expect(all(p["cpu_percent"] is None for p in first["processes"]), "process cpu is null while measuring")
        time.sleep(SAMPLE_GAP_SECONDS)
        second = fetch(one)
        expect(second["measuring"] is False, "the second answer has an earlier sample to compare with")
        expect(isinstance(second["cpu"]["total_percent"], (int, float)), f"cpu total: {second['cpu']['total_percent']!r}")
        expect(len(second["cpu"]["cores_percent"]) == second["cpu"]["core_count"], "one number per core")


def check_the_answer_has_real_looking_memory_disks_and_uptime():
    with helper() as one:
        stats = fetch(one)
        memory = stats["memory"]
        expect(memory["total_bytes"] > 0, "memory total")
        expect(memory["used_bytes"] + memory["cached_bytes"] + memory["free_bytes"] <= memory["total_bytes"], f"used+cached+free passes total: {memory}")
        expect(stats["disks"] and all(d["total_bytes"] >= d["used_bytes"] for d in stats["disks"]), f"disks: {stats['disks']}")
        expect(stats["uptime_seconds"] > 0, "uptime")


def check_processes_are_few_cut_and_never_carry_a_command_line():
    with helper() as one:
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", SECRET_ARGUMENT])
        try:
            fetch(one)
            time.sleep(SAMPLE_GAP_SECONDS)
            status, body = one.call("GET", STATS)
            raw = repr(body)
            expect(status == 200 and len(body["processes"]) <= MAX_PROCESSES, f"processes: {len(body['processes'])}")
            expect(all(len(p["name"]) <= NAME_LIMIT and len(p["user"]) <= NAME_LIMIT for p in body["processes"]), "a name or user was not cut")
            expect(SECRET_ARGUMENT not in raw and "cmdline" not in raw and "command" not in raw, "a command line reached the answer")
        finally:
            child.kill()
            child.wait()


def check_processes_zero_skips_the_list_and_the_rest_stays_whole():
    with helper() as one:
        fetch(one)
        time.sleep(SAMPLE_GAP_SECONDS)
        status, body = one.call("GET", f"{STATS}?processes=0")
        problems = spec.problems("Stats", body)
        expect(status == 200 and not problems, f"processes=0 gave {status}: {problems[:3]}")
        expect(body["processes"] == [], f"no list wanted, none sent: {body['processes']}")
        expect(body["measuring"] is False and body["cpu"]["total_percent"] is not None, "the machine numbers are still there")
        status, with_list = one.call("GET", f"{STATS}?processes=1")
        expect(status == 200 and len(with_list["processes"]) >= 1, "processes=1 keeps the list")


def check_an_unknown_value_of_processes_is_a_plain_400():
    with helper() as one:
        for bad in ("processes=2", "processes=", "processes=yes", "processes=1&processes=0"):
            status, body = one.call("GET", f"{STATS}?{bad}")
            expect(status == 400 and body["error"]["code"] == "invalid_input", f"{bad} gave {status}: {body}")
            expect(not spec.problems("Error", body), f"{bad}: not the plain error shape: {body}")


def check_a_missing_gpu_is_a_missing_key_never_zeros():
    with helper() as one:
        stats = fetch(one)
        expect("gpus" not in stats or (stats["gpus"] and all(g["name"] for g in stats["gpus"])), f"gpus must be absent or real: {stats.get('gpus')}")


def second_answer(one):
    fetch(one)
    time.sleep(SAMPLE_GAP_SECONDS)
    return fetch(one)


def a_real_mac():
    return sys.platform == "darwin" and os.environ.get("MS_HELPER") != "fake"


def check_the_cpu_layout_is_whole_or_left_out():
    with helper() as one:
        cpu = second_answer(one)["cpu"]
        if "physical_cores" in cpu:
            expect(1 <= cpu["physical_cores"] <= cpu["core_count"], f"physical cores {cpu['physical_cores']} of {cpu['core_count']} logical")
        if "core_of" in cpu:
            expect(len(cpu["core_of"]) == cpu["core_count"] and all(0 <= core < cpu["core_count"] for core in cpu["core_of"]), f"core_of: {cpu['core_of']}")
            expect(len(set(cpu["core_of"])) == cpu.get("physical_cores", len(set(cpu["core_of"]))), "core_of and physical_cores disagree")
        for cluster in cpu.get("clusters", []):
            expect(cluster["logical"] >= 1 and cluster["name"], f"cluster: {cluster}")


def check_the_cpu_breakdown_is_known_states_that_add_up_to_the_whole_and_a_mac_gives_four():
    with helper() as one:
        cpu = second_answer(one)["cpu"]
        breakdown = cpu.get("breakdown")
        expect(breakdown is None or isinstance(breakdown, dict), f"breakdown: {breakdown!r}")
        if breakdown:
            expect(set(breakdown) <= BREAKDOWN_STATES, f"unknown states: {set(breakdown) - BREAKDOWN_STATES}")
            expect(all(0 <= share <= FULL_SHARE for share in breakdown.values()), f"a share outside 0..100: {breakdown}")
            expect(abs(sum(breakdown.values()) - FULL_SHARE) <= ROUNDING_ALLOWANCE + len(breakdown) * 0.05, f"the states must add up to the whole: {breakdown}")
        if a_real_mac():
            expect(breakdown is not None and set(breakdown) == MAC_BREAKDOWN_STATES, f"a Mac gives user, system, nice, idle and nothing else: {breakdown}")


def check_frequency_and_temperature_are_real_numbers_or_left_out_and_a_mac_leaves_them_out():
    with helper() as one:
        cpu = second_answer(one)["cpu"]
        for key in ("frequency_mhz", "temperature_celsius"):
            expect(key not in cpu or cpu[key], f"{key} must be left out, never 0: {cpu.get(key)!r}")
        if a_real_mac():
            expect("frequency_mhz" not in cpu and "temperature_celsius" not in cpu, "a Mac gives no frequency or temperature without root")


def check_disk_speed_and_network_counters_are_numbers_or_left_out():
    with helper() as one:
        stats = second_answer(one)
        speed = stats.get("disk_io")
        expect(speed is None or (speed["read_bytes_per_second"] >= 0 and speed["write_bytes_per_second"] >= 0), f"disk_io: {speed}")
        network = stats["network"]
        expect(all(isinstance(network[key], int) and network[key] >= 0 for key in network if key.endswith("_total") and key.split("_")[0] in ("errors", "drops")), f"network counters: {network}")
        if a_real_mac():
            expect(speed is not None, "a Mac gives the disk speed (IOKit, no root)")
            expect("errors_in_total" in network and "drops_out_total" not in network, f"a Mac counts errors both ways and drops in only: {network}")


def check_the_number_of_running_programs_is_at_least_the_list_and_threads_are_whole_numbers():
    with helper() as one:
        stats = second_answer(one)
        if "process_count" in stats:
            expect(stats["process_count"] >= len(stats["processes"]) >= 1, f"process_count {stats['process_count']} for {len(stats['processes'])} listed")
        expect(all(process.get("threads", 1) >= 1 for process in stats["processes"]), "a thread count below one")
        without = one.call("GET", f"{STATS}?processes=0")[1]
        expect("process_count" not in stats or "process_count" in without, "the number of programs also comes without the list")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
