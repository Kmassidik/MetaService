"""The helper's sandbox routes (contract/openapi.yaml): create, list, get, end, delete, the events and the facts, plus the end time the helper keeps itself.

Runs against a Linux helper started with its simulated sandbox engine (`--sandbox simulated`) and, with `python -m contract.agent_tests.runner --fake`,
against the Fake Agent, which answers the same records from the same rules. Both must pass every check.
"""
import json
import os
import secrets
import time
from contextlib import contextmanager

from contract import spec
from contract.agent_tests.checks_terminal import FakeHelper
from contract.agent_tests.support import agent
from contract.root_tests.support import expect

SANDBOXES = "/v1/sandboxes"
EVENTS = "/v1/sandbox-events"
TEMPLATES = "/v1/sandbox-templates"
TEMPLATE = "base"
# Far enough ahead that nothing ends by itself while a check runs.
LATER = "2027-01-01T00:00:00Z"
WAIT_SECONDS = 15
TOKEN_SPACE = "abcdefghijklmnopqrstuvwxyz0123456789"


@contextmanager
def helper():
    """A helper that runs sandboxes: the Fake Agent when MS_HELPER says fake, else a Linux helper with its simulated sandbox engine."""
    if os.environ.get("MS_HELPER") == "fake":
        one = FakeHelper(sandbox=True)
        try:
            yield one
        finally:
            one.stop()
    else:
        with agent(extra=["--sandbox", "simulated"]) as one:
            yield one


def new_id():
    return "".join(secrets.choice(TOKEN_SPACE) for _ in range(20))


def create_body(sandbox_id=None, end_at=LATER, **change):
    body = {"id": sandbox_id or new_id(), "template": TEMPLATE, "vcpu": 2, "ram_mb": 512, "disk_mb": 1024, "end_at": end_at,
            "on_end": "kill", "internet": False, "env_vars": {"A": "1"}, "access_token": secrets.token_hex(24)}
    body.update(change)
    return body


def create(one, body):
    return one.call("POST", SANDBOXES, body)


def code_of(body):
    return ((body or {}).get("error") or {}).get("code")


def expect_shape(name, body, where):
    problems = spec.problems(name, body)
    expect(not problems, f"{where} does not fit the contract: {problems[:3]}")


def listed(one):
    status, body = one.call("GET", SANDBOXES)
    expect(status == 200, f"list gave {status}: {body}")
    expect_shape("SandboxList", body, "the sandbox list")
    return {sandbox["id"]: sandbox for sandbox in body["sandboxes"]}


def check_a_sandbox_is_made_listed_read_and_deleted():
    with helper() as one:
        sandbox = create_body()
        status, made = create(one, sandbox)
        expect(status == 201, f"create gave {status}: {made}")
        expect_shape("Sandbox", made, "the sandbox")
        expect(made["id"] == sandbox["id"] and made["state"] == "running", f"the sandbox is not the one asked for, running: {made}")
        expect(made["end_at"] == LATER, f"the end time was not kept: {made['end_at']}")
        expect("access_token" not in made, "the access token must never come back")
        found = listed(one)
        expect(sandbox["id"] in found, f"the sandbox is not in the list: {sorted(found)}")
        expect(found[sandbox["id"]]["template"] == TEMPLATE, f"the template is not the one asked for: {found[sandbox['id']]}")
        status, read = one.call("GET", f"{SANDBOXES}/{sandbox['id']}")
        expect(status == 200, f"get gave {status}: {read}")
        expect(read["id"] == sandbox["id"] and read["running_ms"] >= 0, f"get answered another sandbox: {read}")
        status, metrics = one.call("GET", f"{SANDBOXES}/{sandbox['id']}/metrics")
        expect(status == 200, f"metrics gave {status}: {metrics}")
        expect_shape("SandboxMetrics", metrics, "the metrics")
        status, _ = one.call("DELETE", f"{SANDBOXES}/{sandbox['id']}")
        expect(status == 204, f"delete gave {status}")
        expect(one.call("GET", f"{SANDBOXES}/{sandbox['id']}")[0] == 404, "a deleted sandbox is still there")
        expect(one.call("DELETE", f"{SANDBOXES}/{sandbox['id']}")[0] == 204, "deleting it again is not answered the same way")
        expect(one.call("DELETE", f"{SANDBOXES}/{new_id()}")[0] == 404, "a sandbox this helper never had must be a 404")


def check_a_retry_with_the_same_id_and_body_makes_no_second_sandbox():
    with helper() as one:
        sandbox = create_body()
        expect(create(one, sandbox)[0] == 201, "the first create was not made")
        status, again = create(one, sandbox)
        expect(status == 200 and again["id"] == sandbox["id"], f"a retry gave {status}: {again}")
        status, refused = create(one, create_body(sandbox["id"], vcpu=4))
        expect(status == 409 and code_of(refused) == "id_taken", f"the same id with another body gave {status}: {refused}")
        expect(len([found for found in listed(one) if found == sandbox["id"]]) == 1, "a retry made a second sandbox")


def check_every_sandbox_refusal_is_the_code_the_contract_names():
    with helper() as one:
        for label, body in (("a template this machine does not have", create_body(template="code-interpreter-v1")),
                            ("a bad id", create_body("short")), ("an unknown field", create_body(pause_on_end=True))):
            status, refused = create(one, body)
            wanted = 409 if label.startswith("a template") else 400
            expect(status == wanted, f"{label}: {status} {refused}")
            expect(code_of(refused) in ("template_not_ready", "invalid_input"), f"{label}: {refused}")
        expect("access_token" not in json.dumps(refused), "a refusal must not repeat the body")
        expect(one.call("GET", f"{SANDBOXES}/{new_id()}")[0] == 404, "an unknown sandbox must be a 404")
        expect(one.call("GET", f"{SANDBOXES}/not-a-sandbox-id")[0] == 404, "a malformed id must be a 404")
        expect(one.call("GET", SANDBOXES, token=None)[0] == 401, "a sandbox route without the token must be a 401")


def check_a_sandbox_end_time_can_be_moved():
    with helper() as one:
        sandbox = create_body()
        expect(create(one, sandbox)[0] == 201, "the create was not made")
        later = "2027-02-01T00:00:00Z"
        status, moved = one.call("PUT", f"{SANDBOXES}/{sandbox['id']}/end", {"end_at": later, "on_end": "kill"})
        expect(status == 200 and moved["end_at"] == later, f"a new end time gave {status}: {moved}")
        expect(one.call("PUT", f"{SANDBOXES}/{sandbox['id']}/end", {"end_at": "tonight", "on_end": "kill"})[0] == 400, "a broken time must be a 400")
        expect(one.call("PUT", f"{SANDBOXES}/{new_id()}/end", {"end_at": later, "on_end": "kill"})[0] == 404, "an unknown sandbox must be a 404")


def check_the_helper_ends_a_sandbox_at_its_time_and_says_so_in_the_events():
    with helper() as one:
        sandbox = create_body(end_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 2)))
        expect(create(one, sandbox)[0] == 201, "the create was not made")
        status, before = one.call("GET", EVENTS + "?after=0")
        expect(status == 200, f"events gave {status}: {before}")
        expect_shape("SandboxEvents", before, "the events")
        last = before["last"]
        expect(last >= 1 and any(event["kind"] == "started" for event in before["events"]), f"no start event: {before}")
        deadline = time.time() + WAIT_SECONDS
        while time.time() < deadline and one.call("GET", f"{SANDBOXES}/{sandbox['id']}")[0] == 200:
            time.sleep(0.5)
        expect(one.call("GET", f"{SANDBOXES}/{sandbox['id']}")[0] == 404, f"the sandbox outlived its end time")
        status, after = one.call("GET", f"{EVENTS}?after={last}")
        expect(status == 200, f"events after {last} gave {status}: {after}")
        ended = [event for event in after["events"] if event["id"] == sandbox["id"] and event["kind"] == "ended"]
        expect(len(ended) == 1, f"no ended event for the sandbox: {after}")
        expect(ended[0].get("reason") == "timeout", f"the reason is not the end time: {ended[0]}")
        expect(after["last"] > last, "the change number did not move")
        status, from_last = one.call("GET", f"{EVENTS}?after={after['last']}")
        expect(status == 200 and from_last["events"] == [], f"an up-to-date reader was given events again: {from_last}")
        for query in ("", "?after=x", "?after=0&limit=0", "?after=0&limit=1001", "?after=0&other=1"):
            expect(one.call("GET", EVENTS + query)[0] == 400, f"the events query {query!r} was not refused")


def check_the_sandbox_templates_and_the_facts_say_what_this_machine_can_do():
    with helper() as one:
        status, body = one.call("GET", TEMPLATES)
        expect(status == 200, f"templates gave {status}: {body}")
        expect_shape("SandboxTemplateList", body, "the template list")
        ready = [template for template in body["templates"] if template["id"] == TEMPLATE]
        expect(len(ready) == 1 and ready[0]["state"] == "ready", f"the base template is not ready: {body}")
        base = listed(one)
        sandbox = create_body()
        expect(create(one, sandbox)[0] == 201, "the create was not made")
        status, facts = one.call("GET", "/v1/facts")
        expect(status == 200, f"facts gave {status}")
        expect_shape("Facts", facts, "the facts")
        expect(facts["capabilities"]["sandbox"] is True, "a helper that runs sandboxes does not say so")
        expect("sandbox" in facts, "its facts say nothing about sandboxes")
        expect_shape("SandboxFacts", facts["sandbox"], "the sandbox facts")
        expect(facts["sandbox"]["running"] == len(base) + 1, f"the facts do not count the running sandboxes: {facts['sandbox']}")
        expect(facts["sandbox"]["booked"]["ram_mb"] >= 512, f"the booked memory is not counted: {facts['sandbox']['booked']}")
        expect(facts["sandbox"]["changes"] >= 1, "the change number never moved")


def check_the_way_into_a_sandbox_says_plainly_that_there_is_no_network_yet():
    with helper() as one:
        sandbox = create_body()
        expect(create(one, sandbox)[0] == 201, "the create was not made")
        status, refused = one.call("GET", f"{SANDBOXES}/{sandbox['id']}/ports/8080/index.html")
        expect(status == 501 and code_of(refused) == "no_port_proxy", f"the port route gave {status}: {refused}")
        status, refused = one.call("GET", f"{SANDBOXES}/{new_id()}/ports/8080/index.html")
        expect(status == 502 and code_of(refused) == "not_found", f"an unknown sandbox on the port route gave {status}: {refused}")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
