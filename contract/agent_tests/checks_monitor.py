"""The helper's monitor route: GET /v1/stats. Runs against the real macOS helper (simulated engine), the Linux helper (where /proc exists), or with
`python -m contract.agent_tests.runner --fake` against the Fake Agent. Rules: docs/monitor-contract.md."""
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


def check_a_missing_gpu_is_a_missing_key_never_zeros():
    with helper() as one:
        stats = fetch(one)
        expect("gpus" not in stats or (stats["gpus"] and all(g["name"] for g in stats["gpus"])), f"gpus must be absent or real: {stats.get('gpus')}")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
