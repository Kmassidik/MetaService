"""The GPU parts of the parent, against a real Root and fake helpers (agent/fake): a machine with an NVIDIA card and the container toolkit, one with the card but
without the toolkit, a Mac, and a machine with no GPU. Covers the refusal of a GPU container, what is stored about a workload's GPU, and the route
POST|GET /api/machines/{id}/workloads/{workload}/gpu-check: its guards, its three answers, hostile text, a VM, a stopped container, a machine that does not answer, and the rate limit."""
import copy
import threading

from agent.fake.engine import GPU_INSIDE, FakeEngine, MachineSpec
from agent.fake.server import make_server
from contract import spec
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.support import Browser, expect, good_heartbeat, running

MACHINE = "mini"
CARD = {"vendor": "nvidia", "model": "NVIDIA GeForce RTX 5090", "memory_mb": 32768}
APPLE = {"vendor": "apple", "model": "Apple M2", "memory_mb": None}
CONTAINER = {"kind": "container", "cpu": 1, "ram_mb": 512, "disk_gb": 1}
TOOLKIT_WORDS = "NVIDIA container toolkit"
NOT_GIVEN_NOTE = "No GPU was given to this one."


def gpu_check_path(workload, machine=MACHINE):
    return f"/api/machines/{machine}/workloads/{workload}/gpu-check"


class GpuHelper:
    """A fake helper on loopback that counts the GPU checks it is asked for."""

    def __init__(self, token, machine_spec):
        self.engine = FakeEngine(machine_spec)
        self.checks = 0
        original = self.engine.gpu_check

        def counted(workload_id):
            self.checks += 1
            return original(workload_id)

        self.engine.gpu_check = counted
        self.server = make_server(self.engine, token, "127.0.0.1", 0)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def make(self, name, kind="container", gpu_mode="container", state="running"):
        """A workload on the helper; returns its id."""
        command = self.engine.create({"command_id": f"c-{name}", "name": name, "kind": kind, "cpu": 1, "ram_mb": 512, "disk_gb": 1, "gpu_mode": gpu_mode})
        workload = command["workload_id"]
        if state != "running":
            self.engine.set_state(f"s-{name}", workload, "stop", state)
        return workload

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


def tell_the_parent(root, machine_token, helper):
    """A heartbeat with the helper's real facts and workloads, as a helper sends it."""
    body = copy.deepcopy(good_heartbeat())
    facts = helper.engine.facts()
    body["facts"] = {key: facts[key] for key in ("os", "arch", "cpu_cores", "cpu_model", "hardware", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities") if key in facts}
    body["workloads"] = helper.engine.workloads()
    body["agent_port"] = helper.port
    reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {machine_token}"}, origin=None)
    expect(reply.status == 204, f"heartbeat gave {reply.status}: {reply.raw[:150]!r}")


def machine_like(operator, root, machine_spec):
    machine_token, command_token = enroll(operator, MACHINE)
    helper = GpuHelper(command_token, machine_spec)
    return helper, lambda: tell_the_parent(root, machine_token, helper)


def check_a_gpu_container_where_containers_cannot_have_the_gpu_is_refused_in_plain_words():
    cases = {
        "a card without the toolkit": MachineSpec(vm=False, gpu=[CARD], gpu_in_container=False),
        "a Mac": MachineSpec(os="macos", arch="arm64", gpu=[APPLE]),
        "a machine without a GPU": MachineSpec(),
    }
    for label, machine_spec in cases.items():
        with running() as root:
            operator = Browser(root)
            helper, beat = machine_like(operator, root, machine_spec)
            try:
                beat()
                reply = operator.write("POST", "/api/workloads", {"name": "g", "machine": MACHINE, "gpu_mode": "container", **CONTAINER})
                error = reply.body["error"]
                expect(reply.status == 409 and error["code"] == "missing_capability", f"{label}: {reply.status} {reply.raw[:200]!r}")
                expect(TOOLKIT_WORDS in error["message"] and "ncus" not in error["message"] and "capability" not in error["message"], f"{label}: the refusal must be plain: {error['message']!r}")
                expect(operator.write("POST", "/api/workloads", {"name": "p", "machine": MACHINE, **CONTAINER}).status == 202, f"{label}: a container without the GPU is still fine")
            finally:
                helper.stop()


def check_a_gpu_container_is_made_stored_and_listed_with_its_gpu_mode():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True))
        try:
            beat()
            reply = operator.write("POST", "/api/workloads", {"name": "g", "machine": MACHINE, "gpu_mode": "container", **CONTAINER})
            expect(reply.status == 202, f"create gave {reply.status}: {reply.raw[:200]!r}")
            beat()
            listed = operator.request("GET", f"/api/machines/{MACHINE}").body["workloads"]
            expect([w["gpu_mode"] for w in listed] == ["container"], f"the parent must store and return gpu_mode: {listed}")
        finally:
            helper.stop()


def check_the_gpu_check_needs_the_session_and_the_right_host_and_knows_its_machines():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True))
        try:
            workload = helper.make("g")
            beat()
            path = gpu_check_path(workload)
            expect(Browser(root, auto_login=False).request("GET", path).status == 401, "no session must be 401 (GET)")
            expect(Browser(root, auto_login=False).request("POST", path, {}).status == 401, "no session must be 401 (POST)")
            expect(operator.request("GET", path, headers={"Host": "evil.example"}).status == 403, "a foreign Host must be 403")
            expect(operator.request("POST", path, {}).status == 403, "a POST without the CSRF token must be 403")
            expect(operator.request("POST", path, {}, origin="https://evil.example").status in (401, 403), "a POST from another origin must be refused")
            expect(operator.request("GET", gpu_check_path(workload, "nobody")).status == 404, "an unknown machine must be 404")
            expect(operator.request("GET", gpu_check_path("wl-99")).status == 404, "an unknown workload must be 404")
            expect(operator.request("GET", gpu_check_path("BAD%20ID")).status == 404, "a malformed id must be 404")
            expect(helper.checks == 0, f"a refused request must not reach the helper: {helper.checks}")
        finally:
            helper.stop()


def check_the_gpu_check_passes_on_each_of_the_three_answers_and_keeps_hostile_text_as_text():
    expected = {"nvidia-smi": (True, "nvidia-smi"), "device nodes": (True, "device nodes"), "none": (False, "none"), "hostile": (True, "nvidia-smi")}
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True))
        try:
            workloads = {inside: helper.make(f"g-{index}") for index, inside in enumerate(expected)}
            beat()
            for index, (inside, workload) in enumerate(workloads.items()):
                helper.engine.spec.gpu_inside = inside
                reply = operator.request("GET", gpu_check_path(workload)) if index % 2 == 0 else operator.write("POST", gpu_check_path(workload))
                expect(reply.status == 200, f"{inside}: {reply.status} {reply.raw[:200]!r}")
                problems = spec.problems("GpuCheck", reply.body)
                expect(not problems, f"{inside}: the reply does not fit the contract: {problems[:3]}")
                expect((reply.body["gpu_visible"], reply.body["how"]) == expected[inside], f"{inside}: {reply.body}")
                expect(reply.header("content-type") == "application/json" and reply.header("x-content-type-options") == "nosniff", f"{inside}: headers")
            expect(GPU_INSIDE["hostile"]["detail"] in reply.body["detail"], f"the hostile text must arrive unchanged, as text: {reply.body}")
            expect(helper.checks == len(expected), f"one helper call each: {helper.checks}")
        finally:
            helper.stop()


def check_a_vm_and_a_container_without_the_gpu_are_answered_by_the_parent_without_asking_the_helper():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(gpu=[CARD], gpu_in_container=True))
        try:
            plain = helper.make("plain", gpu_mode="none")
            vm = helper.make("vm", kind="vm", gpu_mode="none")
            beat()
            for workload in (plain, vm):
                reply = operator.request("GET", gpu_check_path(workload))
                expect(reply.status == 200 and reply.body == {"gpu_visible": False, "how": "none", "detail": "", "note": NOT_GIVEN_NOTE}, f"{workload}: {reply.status} {reply.raw[:200]!r}")
            expect(helper.checks == 0, f"nothing may be asked of the helper: {helper.checks}")
        finally:
            helper.stop()


def check_a_stopped_container_and_a_machine_that_does_not_answer_get_the_usual_errors():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True))
        try:
            stopped = helper.make("off", state="stopped")
            gone = helper.make("gone")
            beat()
            reply = operator.request("GET", gpu_check_path(stopped))
            expect(reply.status == 409 and reply.body["error"]["code"] == "not_running", f"stopped: {reply.status} {reply.raw[:200]!r}")
            helper.stop()
            reply = operator.request("GET", gpu_check_path(gone))
            expect(reply.status == 502 and reply.body["error"]["code"] == "unreachable", f"helper gone: {reply.status} {reply.raw[:200]!r}")
        finally:
            helper.stop()


def check_the_same_container_cannot_be_checked_again_within_five_seconds():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True))
        try:
            workload = helper.make("g")
            other = helper.make("h")
            beat()
            expect(operator.request("GET", gpu_check_path(workload)).status == 200, "the first check")
            again = operator.request("GET", gpu_check_path(workload))
            expect(again.status == 429 and again.body["error"]["code"] == "rate_limited", f"the second: {again.status} {again.raw[:200]!r}")
            expect(operator.request("GET", gpu_check_path(other)).status == 200, "another container is not held back")
            expect(helper.checks == 2, f"the held-back check must not reach the helper: {helper.checks}")
        finally:
            helper.stop()


CHECKS = [check_a_gpu_container_where_containers_cannot_have_the_gpu_is_refused_in_plain_words, check_a_gpu_container_is_made_stored_and_listed_with_its_gpu_mode,
          check_the_gpu_check_needs_the_session_and_the_right_host_and_knows_its_machines, check_the_gpu_check_passes_on_each_of_the_three_answers_and_keeps_hostile_text_as_text,
          check_a_vm_and_a_container_without_the_gpu_are_answered_by_the_parent_without_asking_the_helper, check_a_stopped_container_and_a_machine_that_does_not_answer_get_the_usual_errors,
          check_the_same_container_cannot_be_checked_again_within_five_seconds]
