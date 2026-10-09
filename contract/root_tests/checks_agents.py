"""Enrollment, heartbeat, machine listing, removal and the audit trail."""
import copy

from contract.root_tests.support import Browser, enrolled_machine, expect, good_heartbeat, running
from contract.tests.support import expect_schema

INJECTION_NAMES = ["UPPER", "has space", "semi;colon", "$(reboot)", "`id`", "a/b", "../etc", "-lead", "", "x'; DROP TABLE machines;--",
                   "<script>alert(1)</script>", "a" * 64, "name\nnewline"]


def _beat(token, body, root):
    return Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)


def check_invite_then_enroll_gives_a_long_token():
    with running() as root:
        operator = Browser(root)
        invite = operator.write("POST", "/api/enrollments", {"name": "dgx"})
        expect(invite.status == 201 and len(invite.body["enrollment_token"]) >= 43, f"invite: {invite.status} {invite.body}")
        reply = Browser(root).request("POST", "/v1/agents/enroll", {"enrollment_token": invite.body["enrollment_token"], "name": "dgx"}, origin=None)
        expect(reply.status == 200, f"enroll gave {reply.status}")
        expect_schema("EnrollResponse", reply.body, "enroll reply")


def check_an_enrollment_token_works_once_and_only_for_its_name():
    with running() as root:
        operator = Browser(root)
        token = operator.write("POST", "/api/enrollments", {"name": "dgx"}).body["enrollment_token"]
        agent = Browser(root)
        wrong_name = agent.request("POST", "/v1/agents/enroll", {"enrollment_token": token, "name": "other"}, origin=None)
        first = agent.request("POST", "/v1/agents/enroll", {"enrollment_token": token, "name": "dgx"}, origin=None)
        second = agent.request("POST", "/v1/agents/enroll", {"enrollment_token": token, "name": "dgx"}, origin=None)
        expect((wrong_name.status, first.status, second.status) == (401, 200, 401), f"got {(wrong_name.status, first.status, second.status)}")
        expect_schema("Error", second.body, "second use")


def check_enroll_refusals_look_the_same():
    with running() as root:
        agent = Browser(root)
        guesses = [{"enrollment_token": "z" * 43, "name": "dgx"}, {"enrollment_token": "z" * 16, "name": "dgx"}]
        replies = [agent.request("POST", "/v1/agents/enroll", body, origin=None) for body in guesses]
        expect({reply.raw for reply in replies} == {replies[0].raw}, "different refusals reveal which tokens are close")


def check_bad_machine_names_are_rejected_when_inviting():
    with running() as root:
        operator = Browser(root)
        for name in INJECTION_NAMES:
            reply = operator.write("POST", "/api/enrollments", {"name": name})
            expect(reply.status == 400, f"name {name[:20]!r} gave {reply.status}")
        for raw in (b"{", b"null", b"[]", b'{"name":"a","extra":1}'):
            expect(operator.write("POST", "/api/enrollments", raw=raw).status == 400, f"body {raw!r} was accepted")


def check_cannot_invite_a_name_that_is_already_enrolled():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        reply = operator.write("POST", "/api/enrollments", {"name": "mini"})
        expect(reply.status == 409, f"re-inviting an enrolled machine gave {reply.status}")


def check_a_new_machine_is_offline_until_its_first_heartbeat():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        machine = operator.request("GET", "/api/machines/mini").body
        expect(machine["state"] == "offline" and machine["last_seen"] is None, f"new machine: {machine['state']}")
        expect(_beat(token, good_heartbeat(), root).status == 204, "first heartbeat was refused")
        machine = operator.request("GET", "/api/machines/mini").body
        expect(machine["state"] == "online" and machine["arch"] == "aarch64", f"after heartbeat: {machine['state']} {machine['arch']}")
        expect(machine["workloads"][0]["id"] == "wl-1" and machine["capabilities"]["gpu_in_container"] is True, "facts or workloads not stored")
        listed = operator.request("GET", "/api/machines").body["machines"]
        expect([m["id"] for m in listed] == ["mini"], f"listing: {listed}")


def check_heartbeat_with_a_provisioning_workload_marks_the_machine_busy():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        body = good_heartbeat()
        body["workloads"][0]["state"] = "provisioning"
        _beat(token, body, root)
        expect(operator.request("GET", "/api/machines/mini").body["state"] == "busy", "provisioning did not make the machine busy")


PROBLEM = {"code": "bridge_blocked_by_firewall", "message": "VMs cannot get an IPv4 address", "fix": "Run: metaservice-agent setup --yes"}


def check_a_machine_with_a_reported_problem_shows_it_and_is_refused_new_workloads_until_it_clears():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        _beat(token, good_heartbeat(), root)
        expect(operator.request("GET", "/api/machines/mini").body["problems"] == [], "a ready machine lists problems")
        body = good_heartbeat()
        body["facts"]["problems"] = [PROBLEM]
        expect(_beat(token, body, root).status == 204, "a heartbeat with problems was refused")
        expect(operator.request("GET", "/api/machines/mini").body["problems"] == [PROBLEM], "the problem was not stored")
        refused = operator.write("POST", "/api/workloads", {"name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5})
        expect(refused.status == 409 and refused.body["error"]["code"] == "machine_needs_setup", f"create: {refused.status} {refused.body}")
        _beat(token, good_heartbeat(), root)
        expect(operator.request("GET", "/api/machines/mini").body["problems"] == [], "the problem stayed after it was fixed")
        again = operator.write("POST", "/api/workloads", {"name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5})
        expect(again.body is None or again.body.get("error", {}).get("code") != "machine_needs_setup", "a fixed machine is still refused")


def check_heartbeat_rejects_every_broken_problem_list():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        broken = [[{**PROBLEM, "code": "Bad Code"}], [{**PROBLEM, "message": ""}], [{"code": "x"}], [{**PROBLEM, "extra": 1}], [PROBLEM] * 21,
                  [{**PROBLEM, "fix": "x" * 501}], "text", {"a": 1}]
        for item in broken:
            body = good_heartbeat()
            body["facts"]["problems"] = item
            expect(_beat(token, body, root).status == 400, f"accepted {str(item)[:60]}")
        hostile = good_heartbeat()
        hostile["facts"]["problems"] = [{**PROBLEM, "message": "<img src=x onerror=alert(1)>"}]
        _beat(token, hostile, root)
        expect("<img" in operator.request("GET", "/api/machines/mini").body["problems"][0]["message"], "hostile text must come back as plain JSON text")


def check_the_computer_running_the_control_plane_is_invited_as_the_first_machine():
    import json, os, re, stat, tempfile
    ui = tempfile.mkdtemp(prefix="ms-no-ui-")
    with running(extra_args=["--ui-dir", ui]) as root:
        path = os.path.join(root.dir, "local-agent.json")
        expect(os.path.exists(path) and stat.S_IMODE(os.stat(path).st_mode) == 0o600, "no private invite file for the local Agent")
        invite = json.load(open(path))
        expect(set(invite) == {"name", "token"} and re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", invite["name"]) and len(invite["token"]) >= 43, f"invite file: {invite.keys()}")
        agent = Browser(root, auto_login=False)
        wrong_name = agent.request("POST", "/v1/agents/enroll", {"enrollment_token": invite["token"], "name": "someone-else"}, origin=None)
        expect(wrong_name.status == 401, f"the invite worked for another name: {wrong_name.status}")
        done = agent.request("POST", "/v1/agents/enroll", {"enrollment_token": invite["token"], "name": invite["name"]}, origin=None)
        expect(done.status == 200 and "machine_token" in done.body, f"the local invite was refused: {done.status} {done.raw[:80]!r}")
        expect(agent.request("POST", "/v1/agents/enroll", {"enrollment_token": invite["token"], "name": invite["name"]}, origin=None).status == 401, "the invite worked twice")
        listed = Browser(root).request("GET", "/api/machines").body["machines"]
        expect([m["name"] for m in listed] == [invite["name"]], f"the machine list: {listed}")


def check_with_the_no_local_machine_option_nobody_is_invited():
    import os
    with running() as root:
        expect(not os.path.exists(os.path.join(root.dir, "local-agent.json")), "an invite was made although the option is on")


def check_heartbeat_rejects_every_broken_shape():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        mutations = {
            "extra top field": lambda b: b.update(extra=1), "no facts": lambda b: b.pop("facts"), "os": lambda b: b["facts"].update(os="plan9"),
            "cpu bool": lambda b: b["facts"].update(cpu_cores=True), "cpu float": lambda b: b["facts"].update(cpu_cores=1.5),
            "negative ram": lambda b: b["facts"].update(free_ram_mb=-1), "caps number": lambda b: b["facts"]["capabilities"].update(vm=1),
            "workload id": lambda b: b["workloads"][0].update(id="Bad Id"), "workload state": lambda b: b["workloads"][0].update(state="exploded"),
            "workload extra": lambda b: b["workloads"][0].update(root=True), "bundle version": lambda b: b.update(bundle_version="latest"),
            "too many workloads": lambda b: b.update(workloads=[b["workloads"][0]] * 1001),
        }
        for label, change in mutations.items():
            body = copy.deepcopy(good_heartbeat())
            change(body)
            reply = _beat(token, body, root)
            expect(reply.status in (400, 413), f"{label}: wanted a refusal, got {reply.status}")
            expect_schema("Error", reply.body, label)
        expect(operator.request("GET", "/api/machines/mini").body["last_seen"] is None, "a refused heartbeat still updated the machine")


def check_hostile_text_in_a_heartbeat_comes_back_as_json_text():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        body = good_heartbeat()
        body["workloads"][0]["address"] = "<script>alert(1)</script>"
        expect(_beat(token, body, root).status == 204, "an address with markup was refused")
        reply = operator.request("GET", "/api/machines/mini")
        expect((reply.header("Content-Type") or "").startswith("application/json"), "machine data is not served as JSON")
        expect(reply.body["workloads"][0]["address"] == "<script>alert(1)</script>", "stored text was changed")
        expect(reply.header("X-Content-Type-Options") == "nosniff", "browsers may sniff the JSON as HTML")


def check_tokens_work_only_where_they_belong():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        as_machine = Browser(root, auto_login=False).request("POST", "/api/enrollments", {"name": "other"}, headers={"Authorization": f"Bearer {token}"})
        expect(as_machine.status == 401, f"a machine token opened an operator endpoint: {as_machine.status}")
        as_operator = operator.request("POST", "/v1/agents/heartbeat", good_heartbeat(), headers={"X-CSRF-Token": operator.csrf()})
        expect(as_operator.status == 401, f"an operator session was accepted as a machine: {as_operator.status}")


def check_removing_a_machine_revokes_its_token():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        expect(operator.write("DELETE", "/api/machines/mini").status == 204, "remove failed")
        expect(_beat(token, good_heartbeat(), root).status == 401, "the removed machine can still send heartbeats")
        expect(operator.write("DELETE", "/api/machines/mini").status == 404, "second remove was not a 404")
        expect(operator.request("GET", "/api/machines/mini").status == 404, "removed machine still listed")


def check_hostile_ids_in_paths_are_404_not_errors():
    with running() as root:
        operator = Browser(root)
        for item in ("nope", "..%2Fetc", "UPPER", "%00", "x'%3B%20DROP%20TABLE%20machines%3B--", "a" * 80, "%24%28id%29"):
            reply = operator.request("GET", f"/api/machines/{item}")
            expect(reply.status == 404, f"id {item[:25]} gave {reply.status}")
        expect(operator.request("GET", "/api/machines").status == 200, "the database broke after hostile ids")


def check_audit_records_actions_newest_first_and_cannot_be_changed():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        operator.write("DELETE", "/api/machines/mini")
        entries = operator.request("GET", "/api/audit").body["entries"]
        actions = [entry["action"] for entry in entries]
        for wanted in ("enrollment.create", "machine.enroll", "machine.remove"):
            expect(wanted in actions, f"no {wanted} entry in {actions}")
        expect(actions.index("machine.remove") < actions.index("machine.enroll"), "audit is not newest first")
        ids = [entry["id"] for entry in entries]
        expect(ids == sorted(ids, reverse=True), "ids are not descending")
        expect(all(entry["actor"] for entry in entries), "an entry has no actor")
        expect(operator.write("DELETE", "/api/audit").status == 404 and operator.write("PUT", "/api/audit", {}).status == 404, "the audit log can be changed over HTTP")
        page = operator.request("GET", f"/api/audit?limit=1&before={ids[0]}").body["entries"]
        expect(len(page) == 1 and page[0]["id"] < ids[0], "paging does not work")
        expect(operator.request("GET", "/api/audit?limit=abc&before=x'").status == 200, "odd paging values broke the audit list")


def check_the_enroll_token_is_not_written_to_the_audit_log():
    with running() as root:
        operator = Browser(root)
        token = operator.write("POST", "/api/enrollments", {"name": "mini"}).body["enrollment_token"]
        Browser(root).request("POST", "/v1/agents/enroll", {"enrollment_token": token, "name": "mini"}, origin=None)
        raw = operator.request("GET", "/api/audit").raw
        expect(token.encode() not in raw, "an enrollment token is in the audit log")


CHECKS = [
    check_invite_then_enroll_gives_a_long_token, check_an_enrollment_token_works_once_and_only_for_its_name, check_enroll_refusals_look_the_same,
    check_bad_machine_names_are_rejected_when_inviting, check_cannot_invite_a_name_that_is_already_enrolled,
    check_a_new_machine_is_offline_until_its_first_heartbeat, check_heartbeat_with_a_provisioning_workload_marks_the_machine_busy,
    check_a_machine_with_a_reported_problem_shows_it_and_is_refused_new_workloads_until_it_clears, check_heartbeat_rejects_every_broken_problem_list, check_the_computer_running_the_control_plane_is_invited_as_the_first_machine, check_with_the_no_local_machine_option_nobody_is_invited,
    check_heartbeat_rejects_every_broken_shape, check_hostile_text_in_a_heartbeat_comes_back_as_json_text, check_tokens_work_only_where_they_belong,
    check_removing_a_machine_revokes_its_token, check_hostile_ids_in_paths_are_404_not_errors,
    check_audit_records_actions_newest_first_and_cannot_be_changed, check_the_enroll_token_is_not_written_to_the_audit_log,
]
