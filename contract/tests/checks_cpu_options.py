"""The CPU settings of Proxmox's Processors window: `cpu_sockets`, `cpu_type` and `cpu_flags` on a VM and `cpu_limit_percent` on a container, offered with
`cpu_models`, `cpu_topology`, `cpu_flags` and `cpu_limit` in the facts. Refusals (the wrong kind, out of range, more than the helper offers) are checked on every
helper; a create with a setting runs only on a helper that announces it, and what it makes is deleted again."""
from contract.tests.support import expect, expect_error, expect_schema

HOST_MODEL = "host"
FLAGS = ("nested-virt", "aes")
X86 = "x86_64"
# Models some helpers list, and a well-formed name no helper does: a helper must refuse every model it does not list.
MODELS_ELSEWHERE = ("EPYC", "EPYC-Rome", "EPYC-Milan", "EPYC-Genoa", "Skylake-Server", "Icelake-Server", "No-Such-CPU")
KIND_OF = {"cpu_sockets": "vm", "cpu_type": "vm", "cpu_flags": "vm", "cpu_limit_percent": "container"}
OUT_OF_RANGE = {
    "cpu_sockets": (0, -1, 9, 1.5, "2", True, None),
    "cpu_type": ("", "-host", "EPYC Genoa", "host;reboot", "<b>host</b>", "x" * 41, 5, ["host"], None),
    "cpu_flags": ({}, {"nested-virt": "yes"}, {"aes": True}, {"aes": None}, {"vmx": "on"}, {"svm": "on"}, ["aes"], "aes", None),
    "cpu_limit_percent": (0, 9, -150, 6401, 150.5, "150", True, None),
}


def _base(ctx, kind, **overrides):
    body = {"command_id": ctx.new_id("c"), "name": ctx.new_id("w"), "kind": kind, "cpu": 1, "ram_mb": 512, "disk_gb": 1}
    body.update(overrides)
    return body


def _capabilities(ctx):
    return ctx.facts().get("capabilities", {})


def _refused(ctx, body, label):
    reply = ctx.post("/v1/workloads", body)
    expect_error(reply, 400, label)
    expect(reply.body["error"]["code"] == "invalid_input", f"{label}: wrong code {reply.body}")


def _made_and_deleted(ctx, body, label):
    """The create works and the workload is listed as any other (the list does not carry CPU settings); it is deleted again so it holds no room."""
    reply = ctx.post("/v1/workloads", body)
    expect(reply.status == 202, f"{label} gave {reply.status}: {reply.body}")
    done = ctx.wait_for(reply.body["command_id"])
    listed = [w for w in ctx.workloads() if w["id"] == done["workload_id"]]
    expect(len(listed) == 1 and (listed[0]["kind"], listed[0]["cpu"]) == (body["kind"], body["cpu"]), f"{label} is not listed as asked: {listed}")
    expect_schema("Workload", listed[0], label)
    ctx.wait_for(ctx.delete(f"/v1/workloads/{done['workload_id']}").body["command_id"])


def check_cpu_models_start_with_host_and_only_an_x86_machine_lists_nested_virt(ctx):
    facts = ctx.facts()
    capabilities = facts["capabilities"]
    models = capabilities.get("cpu_models", [HOST_MODEL])
    expect(models[:1] == [HOST_MODEL], f"cpu_models must start with host: {models}")
    nested = "nested-virt" in capabilities.get("cpu_flags", [])
    expect(not nested or facts["arch"] == X86, f"nested-virt is svm or vmx, an x86 flag, but this machine is {facts['arch']}")


def check_cpu_settings_on_the_wrong_kind_are_refused(ctx):
    wrong = {"container": {"cpu_sockets": 2, "cpu_type": HOST_MODEL, "cpu_flags": {"aes": "on"}}, "vm": {"cpu_limit_percent": 100}}
    for kind, fields in wrong.items():
        for field, value in fields.items():
            _refused(ctx, _base(ctx, kind, cpu=2, **{field: value}), f"{field} on a {kind}")


def check_cpu_settings_out_of_range_are_refused(ctx):
    for field, values in OUT_OF_RANGE.items():
        for bad in values:
            _refused(ctx, _base(ctx, KIND_OF[field], cpu=64, **{field: bad}), f"{field} {bad!r}")


def check_cpu_must_be_a_multiple_of_the_sockets(ctx):
    for cpu, sockets in ((3, 2), (1, 2), (6, 4), (7, 8)):
        _refused(ctx, _base(ctx, "vm", cpu=cpu, cpu_sockets=sockets), f"{cpu} CPUs over {sockets} sockets")


def check_a_cpu_cap_over_cpu_times_100_is_refused(ctx):
    for cpu, percent in ((1, 101), (2, 201), (16, 1601)):
        _refused(ctx, _base(ctx, "container", cpu=cpu, cpu_limit_percent=percent), f"a cap of {percent}% on {cpu} CPUs")


def check_cpu_settings_the_helper_does_not_announce_are_refused(ctx):
    """Only where the kind itself can be made: a machine without VMs may refuse a VM with 409 before it looks at the CPU."""
    capabilities = _capabilities(ctx)
    if capabilities["vm"]:
        models = capabilities.get("cpu_models", [HOST_MODEL])
        for model in MODELS_ELSEWHERE:
            if model not in models:
                _refused(ctx, _base(ctx, "vm", cpu_type=model), f"cpu_type {model}, which the helper does not list")
        if not capabilities.get("cpu_topology"):
            _refused(ctx, _base(ctx, "vm", cpu=2, cpu_sockets=2), "cpu_sockets on a helper without cpu_topology")
        for flag in FLAGS:
            if flag not in capabilities.get("cpu_flags", []):
                _refused(ctx, _base(ctx, "vm", cpu_flags={flag: "on"}), f"the flag {flag}, which the helper does not list")
    if capabilities["container"] and not capabilities.get("cpu_limit"):
        _refused(ctx, _base(ctx, "container", cpu=2, cpu_limit_percent=150), "cpu_limit_percent on a helper without cpu_limit")


def check_announced_sockets_are_accepted_on_a_vm(ctx):
    capabilities = _capabilities(ctx)
    if not (capabilities["vm"] and capabilities.get("cpu_topology")):
        return
    for cpu, sockets in ((4, 1), (4, 2), (4, 4), (8, 8)):
        _made_and_deleted(ctx, _base(ctx, "vm", cpu=cpu, cpu_sockets=sockets), f"a VM with {cpu} CPUs over {sockets} sockets")


def check_each_announced_cpu_model_is_accepted_on_a_vm(ctx):
    capabilities = _capabilities(ctx)
    if not capabilities["vm"]:
        return
    for model in capabilities.get("cpu_models", []):
        _made_and_deleted(ctx, _base(ctx, "vm", cpu_type=model), f"a VM with cpu_type {model}")


def check_each_announced_cpu_flag_is_accepted_on_and_off(ctx):
    capabilities = _capabilities(ctx)
    if not capabilities["vm"]:
        return
    for flag in capabilities.get("cpu_flags", []):
        for setting in ("on", "off"):
            _made_and_deleted(ctx, _base(ctx, "vm", cpu_flags={flag: setting}), f"a VM with {flag} {setting}")


def check_sockets_a_model_and_flags_together_are_accepted_on_a_vm(ctx):
    capabilities = _capabilities(ctx)
    models, flags = capabilities.get("cpu_models", []), capabilities.get("cpu_flags", [])
    if not (capabilities["vm"] and capabilities.get("cpu_topology") and models and flags):
        return
    together = {"cpu_sockets": 2, "cpu_type": models[-1], "cpu_flags": {flag: "on" if index % 2 == 0 else "off" for index, flag in enumerate(flags)}}
    _made_and_deleted(ctx, _base(ctx, "vm", cpu=4, **together), f"a VM with {together}")


def check_an_announced_cpu_cap_is_accepted_on_a_container(ctx):
    capabilities = _capabilities(ctx)
    if not (capabilities["container"] and capabilities.get("cpu_limit")):
        return
    for cpu, percent in ((1, 10), (2, 150), (2, 200)):
        _made_and_deleted(ctx, _base(ctx, "container", cpu=cpu, cpu_limit_percent=percent), f"a container with {cpu} CPUs capped at {percent}%")


def check_refused_cpu_settings_leave_nothing_behind(ctx):
    before = {w["id"] for w in ctx.workloads()}
    for body in (_base(ctx, "container", cpu=2, cpu_sockets=2), _base(ctx, "vm", cpu=3, cpu_sockets=2), _base(ctx, "vm", cpu_type="No-Such-CPU"),
                 _base(ctx, "container", cpu_limit_percent=101)):
        ctx.post("/v1/workloads", body)
    expect({w["id"] for w in ctx.workloads()} == before, "a refused create left a workload behind")


CHECKS = [check_cpu_models_start_with_host_and_only_an_x86_machine_lists_nested_virt, check_cpu_settings_on_the_wrong_kind_are_refused,
          check_cpu_settings_out_of_range_are_refused, check_cpu_must_be_a_multiple_of_the_sockets, check_a_cpu_cap_over_cpu_times_100_is_refused,
          check_cpu_settings_the_helper_does_not_announce_are_refused, check_announced_sockets_are_accepted_on_a_vm, check_each_announced_cpu_model_is_accepted_on_a_vm,
          check_each_announced_cpu_flag_is_accepted_on_and_off, check_sockets_a_model_and_flags_together_are_accepted_on_a_vm,
          check_an_announced_cpu_cap_is_accepted_on_a_container, check_refused_cpu_settings_leave_nothing_behind]
