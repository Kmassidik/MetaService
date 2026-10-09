"""The macOS Agent beyond the shared contract: real facts, token handling, lockout, enrolling and heartbeats against a real Root."""
import os
import stat
import subprocess

from contract.agent_tests.support import RunningAgent, agent, run_cli, wait_for, write_secret
from contract.root_tests.support import Browser, expect, running as running_root, ALLOWED_EMAIL

GB = 1_000_000_000


def sysctl(name):
    return int(subprocess.run(["sysctl", "-n", name], capture_output=True, text=True).stdout.strip())


def check_facts_describe_this_mac():
    with agent() as one:
        status, facts = one.call("GET", "/v1/facts")
        expect(status == 200 and facts["os"] in ("macos", "linux"), f"facts: {status} {facts}")
        expect(facts["arch"] in ("arm64", "aarch64", "x86_64"), f"arch {facts['arch']}")
        expect(facts["cpu_cores"] == sysctl("hw.activecpu"), f"cores {facts['cpu_cores']} vs {sysctl('hw.activecpu')}")
        expect(facts["ram_total_mb"] == sysctl("hw.memsize") // (1024 * 1024), "RAM total is not what the machine reports")
        expect(10 <= facts["disk_total_gb"] <= 100_000, f"disk total {facts['disk_total_gb']}")
        expect(facts["free_ram_mb"] <= facts["ram_total_mb"] and facts["free_disk_gb"] <= facts["disk_total_gb"], "free is larger than total")
        expect(facts["capabilities"]["vm"] is True and facts["capabilities"]["gpu_in_vm"] is False, f"capabilities {facts['capabilities']}")
        expect(all(g["vendor"] and g["model"] for g in facts["gpu"]), f"gpu list {facts['gpu']}")


def check_allowances_and_reserves_shape_the_free_numbers():
    with agent(extra=["--ram-allowance-mb", "8000", "--ram-reserve-mb", "1000", "--disk-allowance-gb", "100", "--disk-reserve-gb", "10"]) as one:
        facts = one.call("GET", "/v1/facts")[1]
        expect(facts["free_ram_mb"] == 7000, f"free RAM {facts['free_ram_mb']}, wanted 7000")
        expect(facts["free_disk_gb"] == 100 - 10 - 20, f"free disk {facts['free_disk_gb']}, wanted 70")


def check_the_real_disk_can_refuse_even_when_the_budget_allows():
    # A budget that allows nearly the whole disk, and a request the budget accepts but the file system cannot hold.
    with agent(extra=["--disk-allowance-gb", "99999", "--disk-reserve-gb", "0"]) as one:
        facts = one.call("GET", "/v1/facts")[1]
        wanted = facts["disk_total_gb"] - 25
        if wanted > facts["free_disk_gb"] or wanted < 1:
            raise AssertionError("cannot build this check on this machine's disk")
        status, reply = one.call("POST", "/v1/workloads", {"command_id": "c-disk", "name": "big", "kind": "container", "cpu": 1, "ram_mb": 512, "disk_gb": wanted})
        if status == 202:
            raise AssertionError("this disk is nearly empty, so the real-disk path cannot be shown; use a fuller disk")
        detail = reply["error"]
        expect(status == 409 and detail["resource"] == "disk_gb" and detail["needed"] == wanted, f"{status} {reply}")
        expect(detail["free"] < facts["free_disk_gb"], f"the refusal used the budget ({detail['free']}), not the real disk")


def check_wrong_tokens_lock_the_caller_out():
    with agent() as one:
        codes = [one.call("GET", "/v1/health", token=f"wrong-{i}")[0] for i in range(12)]
        expect(codes[:10] == [401] * 10 and 429 in codes[10:], f"codes {codes}")
        expect(one.call("GET", "/v1/health")[0] == 429, "the lockout let the right token through")


def check_the_agent_refuses_a_token_file_others_can_read_or_none_at_all():
    for kwargs in ({"token_mode": 0o644}, {"with_token": False}):
        one = RunningAgent(**kwargs)
        try:
            one.start()
        except AssertionError:
            code, text = one.early_exit
            expect(code != 0 and ("mode 600" in text or "no token in" in text), f"{kwargs}: exit {code}: {text[:100]}")
            continue
        finally:
            one.stop()
        raise AssertionError(f"the Agent started with {kwargs}")


def check_command_line_never_takes_secrets_as_plain_arguments():
    code, _, text = run_cli(["enroll", "--root", "http://127.0.0.1:1", "--name", "x", "--enrollment-token", "secret"])
    expect(code != 0 and "unknown or incomplete option" in text, f"a plain --enrollment-token was accepted: {code} {text[:100]}")
    code, _, text = run_cli(["enroll", "--root", "http://127.0.0.1:1", "--name", "x", "--state-dir", "/tmp/ms-none"], env={"MS_ENROLLMENT_TOKEN": ""})
    expect(code != 0 and "enrollment token" in text, f"enrolling without any token: {code} {text[:100]}")
    for bad in (["--root", "ftp://x", "--name", "x"], ["--root", "http://user:pw@127.0.0.1", "--name", "x"], ["--root", "http://127.0.0.1", "--name", "Bad Name"]):
        code, _, text = run_cli(["enroll"] + bad, env={"MS_ENROLLMENT_TOKEN": "x" * 43})
        expect(code != 0, f"enrolled with {bad}")


def check_enrolling_then_heartbeats_put_this_mac_on_the_roots_list():
    with running_root() as root:
        operator = Browser(root)
        operator.sign_in()
        invite = operator.write("POST", "/api/enrollments", {"name": "this-mac", "ip": "127.0.0.1"}).body["enrollment_token"]
        state = RunningAgent(with_token=False).state
        token_file = os.path.join(state, "enroll.token")
        write_secret(token_file, invite)
        code, out, text = run_cli(["enroll", "--root", f"http://127.0.0.1:{root.port}", "--name", "this-mac", "--enrollment-token-file", token_file, "--state-dir", state])
        expect(code == 0, f"enroll failed: {code} {text[:150]}")
        for name in ("agent.token", "command.token"):
            mode = stat.S_IMODE(os.stat(os.path.join(state, name)).st_mode)
            expect(mode == 0o600, f"{name} has mode {oct(mode)}")
        expect(open(os.path.join(state, "agent.token")).read() != open(os.path.join(state, "command.token")).read(), "the two tokens are the same")
        reuse = run_cli(["enroll", "--root", f"http://127.0.0.1:{root.port}", "--name", "this-mac", "--enrollment-token-file", token_file, "--state-dir", state])
        expect(reuse[0] != 0, "a used enrollment token enrolled twice")
        one = RunningAgent(with_token=False, extra=["--heartbeat-seconds", "1"])
        one.state, one.token = state, open(os.path.join(state, "command.token")).read().strip()
        one.start()
        try:
            machine = wait_for(lambda: (m := operator.request("GET", "/api/machines/this-mac").body) and m["state"] == "online" and m, 20, "the Root never saw a heartbeat")
            facts = one.call("GET", "/v1/facts")[1]
            expect(machine["os"] in ("macos", "linux") and machine["cpu_cores"] == facts["cpu_cores"] and machine["ram_total_mb"] == facts["ram_total_mb"], f"the Root's copy differs: {machine}")
            expect(machine["capabilities"]["vm"] is True, "capabilities did not reach the Root")
            made = one.call("POST", "/v1/workloads", {"command_id": "c-hb", "name": "from-hb", "kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1})
            expect(made[0] == 202, f"create gave {made[0]}")
            wait_for(lambda: any(w["name"] == "from-hb" for w in operator.request("GET", "/api/machines/this-mac").body["workloads"]), 25, "a new workload never reached the Root")
        finally:
            one.stop()


def check_a_missing_root_does_not_stop_the_agent():
    with agent() as one:
        write_secret(os.path.join(one.state, "agent.json"), '{"root": "http://127.0.0.1:9", "name": "x"}')
        write_secret(os.path.join(one.state, "agent.token"), "x" * 43)
        one.stop()
        one.start()
        expect(one.call("GET", "/v1/health")[0] == 200, "the Agent stopped serving because the Root is unreachable")


CHECKS = [
    check_facts_describe_this_mac, check_allowances_and_reserves_shape_the_free_numbers, check_the_real_disk_can_refuse_even_when_the_budget_allows,
    check_wrong_tokens_lock_the_caller_out, check_the_agent_refuses_a_token_file_others_can_read_or_none_at_all,
    check_command_line_never_takes_secrets_as_plain_arguments, check_enrolling_then_heartbeats_put_this_mac_on_the_roots_list,
    check_a_missing_root_does_not_stop_the_agent,
]
