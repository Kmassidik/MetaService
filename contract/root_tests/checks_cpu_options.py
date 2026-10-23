"""The CPU settings of Proxmox's Processors window, against a real Root and a fake helper (agent/fake): GET /api/machines carries each machine's cpu_models,
cpu_topology, cpu_flags and cpu_limit and follows every heartbeat; POST /api/workloads passes cpu_sockets, cpu_type, cpu_flags and cpu_limit_percent to the helper
under the contract's names and only when they differ from before (two sockets or more, a type other than host), refuses a setting on the wrong kind or out of range
with a 400 and one the machine does not offer with a 409 missing_capability, and a refused create never reaches the helper. The Root takes 20 creates a minute
from one address, refused ones too, so no check here asks for more."""
import copy

from agent.fake.engine import CPU_FLAGS, CPU_MODELS, CPU_OPTIONS, MachineSpec
from contract.root_tests.checks_apps import expect_refused
from contract.root_tests.checks_gpu import MACHINE, GpuHelper, machine_like, tell_the_parent
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.checks_remote_install import wait_command
from contract.root_tests.support import Browser, expect, good_heartbeat, running

VM = {"kind": "vm", "cpu": 4, "ram_mb": 1024, "disk_gb": 5}
CONTAINER = {"kind": "container", "cpu": 2, "ram_mb": 512, "disk_gb": 1}
WITH_CPU_OPTIONS = MachineSpec(**CPU_OPTIONS)
SOME_CPU_OPTIONS = MachineSpec(cpu_models=("host", "EPYC"), cpu_flags=("aes",))
OLD_HELPER = MachineSpec()
# What GET /api/machines shows for each of them, read as the contract reads a capability that is left out.
EVERYTHING = {"cpu_models": list(CPU_MODELS), "cpu_topology": True, "cpu_flags": list(CPU_FLAGS), "cpu_limit": True}
SOME = {"cpu_models": ["host", "EPYC"], "cpu_topology": False, "cpu_flags": ["aes"], "cpu_limit": False}
NOTHING = {"cpu_models": ["host"], "cpu_topology": False, "cpu_flags": [], "cpu_limit": False}
PROXMOX_LIKE = {"cpu_sockets": 2, "cpu_type": "EPYC-Genoa", "cpu_flags": {"nested-virt": "on", "aes": "off"}}
# Well formed, so only a machine's own list can refuse it.
UNLISTED_MODEL = "EPYC-Turin"
HOSTILE_ORIGIN = "http://evil.example"


def create(operator, name, base=VM, machine=MACHINE, **settings):
    body = {"name": name, **base, **settings}
    if machine is not None:
        body["machine"] = machine
    return operator.write("POST", "/api/workloads", body)


def made(operator, beat, name, base=VM, machine=MACHINE, **settings):
    """A create through the panel, accepted and finished, then a heartbeat with the helper's list (refused if that list carried anything the parent does not know)."""
    reply = create(operator, name, base, machine, **settings)
    expect(reply.status == 202, f"create {name} with {settings} gave {reply.status}: {reply.raw[:200]!r}")
    wait_command(operator, reply.body["command"]["id"], "succeeded")
    beat()


def cpu_sent(helper, name):
    """The CPU settings the helper was sent for the workload called `name`."""
    request = next(r for r in helper.engine.created_requests if r["name"] == name)
    return {key: value for key, value in request.items() if key.startswith("cpu_")}


def offer_listed(operator, machine=MACHINE):
    """The machine's CPU capabilities as GET /api/machines shows them. One that is left out reads as the contract says: host only, one socket, no flags, no cap."""
    listed = next(m for m in operator.request("GET", "/api/machines").body["machines"] if m["id"] == machine)
    capabilities = listed["capabilities"]
    return {"cpu_models": capabilities.get("cpu_models") or ["host"], "cpu_topology": capabilities.get("cpu_topology", False),
            "cpu_flags": capabilities.get("cpu_flags", []), "cpu_limit": capabilities.get("cpu_limit", False)}


def no_commands(operator):
    commands = operator.request("GET", "/api/commands").body["commands"]
    expect(commands == [], f"a refused create left a command behind: {commands}")


def check_the_machine_list_carries_each_machines_cpu_settings_and_follows_every_heartbeat():
    with running() as root:
        operator = Browser(root)
        other_token, other_command_token = enroll(operator, "other")
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        other = GpuHelper(other_command_token, SOME_CPU_OPTIONS)
        try:
            beat()
            tell_the_parent(root, other_token, other)
            expect(offer_listed(operator) == EVERYTHING, f"{MACHINE}: {offer_listed(operator)}")
            expect(offer_listed(operator, "other") == SOME, f"other: {offer_listed(operator, 'other')}")
            helper.engine.spec = OLD_HELPER  # the helper was replaced by one from before the CPU settings
            beat()
            expect(offer_listed(operator) == NOTHING, f"after a heartbeat that says nothing: {offer_listed(operator)}")
            expect_refused(create(operator, "two-sockets", cpu_sockets=2), 409, "missing_capability", "sockets after the helper stopped offering them")
            helper.engine.spec = WITH_CPU_OPTIONS
            beat()
            expect(offer_listed(operator) == EVERYTHING, f"after the newer helper came back: {offer_listed(operator)}")
            expect(offer_listed(operator, "other") == SOME, "a heartbeat of one machine changed another")
        finally:
            helper.stop()
            other.stop()


def check_a_vm_gets_sockets_type_and_flags_under_the_contracts_names_and_nothing_that_is_as_before():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        try:
            beat()
            made(operator, beat, "proxmox-like", **PROXMOX_LIKE)
            expect(cpu_sent(helper, "proxmox-like") == PROXMOX_LIKE, f"the helper was sent {cpu_sent(helper, 'proxmox-like')}")
            made(operator, beat, "eight-sockets", cpu=8, cpu_sockets=8)
            expect(cpu_sent(helper, "eight-sockets") == {"cpu_sockets": 8}, f"the helper was sent {cpu_sent(helper, 'eight-sockets')}")
            made(operator, beat, "one-flag", cpu_flags={"aes": "on"})
            expect(cpu_sent(helper, "one-flag") == {"cpu_flags": {"aes": "on"}}, f"the helper was sent {cpu_sent(helper, 'one-flag')}")
            made(operator, beat, "as-before", cpu_sockets=1, cpu_type="host")
            expect(cpu_sent(helper, "as-before") == {}, f"one socket and the host CPU are what every VM got before, so nothing is sent: {cpu_sent(helper, 'as-before')}")
            made(operator, beat, "plain")
            expect(cpu_sent(helper, "plain") == {}, f"a create without CPU settings must not send any: {cpu_sent(helper, 'plain')}")
            listed = {w["name"] for w in operator.request("GET", f"/api/machines/{MACHINE}").body["workloads"]}
            expect({"proxmox-like", "eight-sockets", "one-flag", "as-before", "plain"} <= listed, f"the VMs did not reach the panel: {listed}")
        finally:
            helper.stop()


def check_a_container_gets_its_cpu_cap_as_cpu_limit_percent_and_none_when_it_asks_for_none():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        try:
            beat()
            for name, percent in (("capped", 150), ("lowest-cap", 10), ("whole-cap", 200)):
                made(operator, beat, name, CONTAINER, cpu_limit_percent=percent)
                expect(cpu_sent(helper, name) == {"cpu_limit_percent": percent}, f"{name}: the helper was sent {cpu_sent(helper, name)}")
            made(operator, beat, "uncapped", CONTAINER)
            expect(cpu_sent(helper, "uncapped") == {}, f"a container without a cap must not send one: {cpu_sent(helper, 'uncapped')}")
        finally:
            helper.stop()


def check_a_cpu_setting_on_the_wrong_kind_or_out_of_step_with_cpu_is_a_400_and_reaches_nothing():
    wrong = [(CONTAINER, {"cpu_sockets": 2}), (CONTAINER, {"cpu_type": "EPYC"}), (CONTAINER, {"cpu_flags": {"aes": "on"}}), (VM, {"cpu_limit_percent": 150}),
             (VM, {"cpu": 3, "cpu_sockets": 2}), (VM, {"cpu": 1, "cpu_sockets": 2}), (CONTAINER, {"cpu": 1, "cpu_limit_percent": 101}),
             (CONTAINER, {"cpu": 2, "cpu_limit_percent": 201})]
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        try:
            beat()
            for base, settings in wrong:
                expect_refused(create(operator, "x", base, **settings), 400, "invalid_input", f"a {base['kind']} with {settings}")
            expect(helper.engine.created_requests == [], f"a refused create reached the helper: {helper.engine.created_requests}")
            no_commands(operator)
        finally:
            helper.stop()


def check_a_cpu_setting_out_of_range_is_a_400_and_reaches_nothing():
    bad = {"cpu_sockets": (0, 9, "2", True), "cpu_type": ("", "EPYC Genoa", "<script>", "x" * 41), "cpu_flags": ({"vmx": "on"}, {"aes": "yes"}, ["aes"]),
           "cpu_limit_percent": (9, 6401, "150")}
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        try:
            beat()
            for name, values in bad.items():
                base = CONTAINER if name == "cpu_limit_percent" else VM
                for value in values:
                    expect_refused(create(operator, "x", {**base, "cpu": 64}, **{name: value}), 400, "invalid_input", f"{name} {value!r}")
            expect(helper.engine.created_requests == [], f"a refused create reached the helper: {helper.engine.created_requests}")
            no_commands(operator)
        finally:
            helper.stop()


def check_what_the_machine_does_not_offer_is_a_409_missing_capability_in_plain_words_and_reaches_nothing():
    refused_everywhere = [(VM, {"cpu_sockets": 2}), (VM, {"cpu_type": "EPYC-Genoa"}), (VM, {"cpu_flags": {"nested-virt": "on"}}), (CONTAINER, {"cpu_limit_percent": 150})]
    cases = {
        "a helper from before the CPU settings": (OLD_HELPER, refused_everywhere, []),
        "a helper with some of them": (SOME_CPU_OPTIONS, refused_everywhere, [(VM, {"cpu_type": "EPYC"}), (VM, {"cpu_flags": {"aes": "off"}})]),
        "a helper with all of them": (WITH_CPU_OPTIONS, [(VM, {"cpu_type": UNLISTED_MODEL})], [(VM, {"cpu_type": "EPYC-Genoa"})]),
    }
    for label, (machine_spec, refused, offered) in cases.items():
        with running() as root:
            operator = Browser(root)
            helper, beat = machine_like(operator, root, machine_spec)
            try:
                beat()
                for base, settings in refused:
                    reply = create(operator, "x", base, **settings)
                    expect_refused(reply, 409, "missing_capability", f"{label}: a {base['kind']} with {settings}")
                    words = reply.body["error"]["message"]
                    expect(words.strip() and "capabilit" not in words, f"{label}: the refusal must say why in plain words: {words!r}")
                expect(helper.engine.created_requests == [], f"{label}: a refused create reached the helper: {helper.engine.created_requests}")
                no_commands(operator)
                for index, (base, settings) in enumerate(offered):
                    made(operator, beat, f"offered-{index}", base, **settings)
                    expect(cpu_sent(helper, f"offered-{index}") == settings, f"{label}: the helper was sent {cpu_sent(helper, f'offered-{index}')}")
                made(operator, beat, "as-before", cpu_sockets=1, cpu_type="host")
                expect(cpu_sent(helper, "as-before") == {}, f"{label}: one socket and the host CPU work on every machine and send nothing")
            finally:
                helper.stop()


def check_a_create_that_names_no_machine_goes_where_its_cpu_settings_are_offered():
    with running() as root:
        operator = Browser(root)
        roomy_token, roomy_command_token = enroll(operator, "roomy")
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        roomy = GpuHelper(roomy_command_token, MachineSpec(ram_total_mb=131072))
        try:
            beat()
            tell_the_parent(root, roomy_token, roomy)
            made(operator, beat, "plain", machine=None)
            expect([r["name"] for r in roomy.engine.created_requests] == ["plain"], "a plain VM should go to the machine with the most room")
            made(operator, beat, "two-sockets", machine=None, cpu_sockets=2)
            expect(cpu_sent(helper, "two-sockets") == {"cpu_sockets": 2}, f"the VM with two sockets went elsewhere: {helper.engine.created_requests}")
            expect([r["name"] for r in roomy.engine.created_requests] == ["plain"], "the machine without sockets was sent a VM with two")
            expect_refused(create(operator, "nowhere", machine=None, cpu_type=UNLISTED_MODEL), 409, "missing_capability", "a model no machine lists")
        finally:
            helper.stop()
            roomy.stop()


def heartbeat_of(helper):
    """The heartbeat the helper sends (as tell_the_parent builds it), for a check to break one part of."""
    body = copy.deepcopy(good_heartbeat())
    facts = helper.engine.facts()
    body["facts"] = {key: facts[key] for key in ("os", "arch", "cpu_cores", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities")}
    body["workloads"] = helper.engine.workloads()
    body["agent_port"] = helper.port
    return body


def check_a_heartbeat_with_broken_cpu_capabilities_is_refused_and_changes_nothing():
    broken = {
        "models that are not a list": {"cpu_models": "host"}, "a model with a space": {"cpu_models": ["host", "EPYC Genoa"]},
        "markup as a model": {"cpu_models": ["host", "<img src=x onerror=alert(1)>"]}, "65 models": {"cpu_models": ["host"] + [f"m{index}" for index in range(64)]},
        "a model twice": {"cpu_models": ["host", "EPYC", "EPYC"]}, "an unknown flag": {"cpu_flags": ["vmx"]}, "a flag twice": {"cpu_flags": ["aes", "aes"]},
        "sockets as a number": {"cpu_topology": 1}, "the cap as text": {"cpu_limit": "yes"},
    }
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, WITH_CPU_OPTIONS)
        try:
            tell_the_parent(root, machine_token, helper)
            for label, change in broken.items():
                body = heartbeat_of(helper)
                body["facts"]["capabilities"].update(change)
                reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {machine_token}"}, origin=None)
                expect(reply.status == 400, f"{label}: wanted a refusal, got {reply.status}")
            expect(offer_listed(operator) == EVERYTHING, f"a refused heartbeat changed the machine: {offer_listed(operator)}")
        finally:
            helper.stop()


def check_creating_with_cpu_settings_has_the_same_guards_as_any_create():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_CPU_OPTIONS)
        try:
            beat()
            body = {"name": "guarded", "machine": MACHINE, **VM, **PROXMOX_LIKE}
            expect(Browser(root, auto_login=False).request("POST", "/api/workloads", body).status == 401, "no session must be 401")
            expect(operator.request("POST", "/api/workloads", body).status == 403, "no CSRF token must be 403")
            expect(operator.write("POST", "/api/workloads", body, origin=HOSTILE_ORIGIN).status == 403, "a foreign Origin must be 403")
            expect(helper.engine.created_requests == [], "a refused create reached the helper")
        finally:
            helper.stop()


CHECKS = [check_the_machine_list_carries_each_machines_cpu_settings_and_follows_every_heartbeat,
          check_a_vm_gets_sockets_type_and_flags_under_the_contracts_names_and_nothing_that_is_as_before,
          check_a_container_gets_its_cpu_cap_as_cpu_limit_percent_and_none_when_it_asks_for_none,
          check_a_cpu_setting_on_the_wrong_kind_or_out_of_step_with_cpu_is_a_400_and_reaches_nothing, check_a_cpu_setting_out_of_range_is_a_400_and_reaches_nothing,
          check_what_the_machine_does_not_offer_is_a_409_missing_capability_in_plain_words_and_reaches_nothing,
          check_a_create_that_names_no_machine_goes_where_its_cpu_settings_are_offered, check_a_heartbeat_with_broken_cpu_capabilities_is_refused_and_changes_nothing,
          check_creating_with_cpu_settings_has_the_same_guards_as_any_create]
