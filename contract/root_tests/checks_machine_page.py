"""What the machine page reads (GET /api/machines/{id}) and what it changes (PATCH /api/machines/{id}/settings), with hostile input on every new field."""
import copy
import json

from contract.root_tests.support import Browser, enrolled_machine, expect, good_heartbeat, running

HOSTILE = ["'; DROP TABLE machines;--", "<script>alert(1)</script>", "$(reboot)", "`id`", "../../etc/passwd", "line\nbreak", "nul\u0000byte", "x" * 1000, "{@html x}", "--privileged",
           "a b", "; reboot", "%s%n", "Ünïcode", "", " "]
TEXT_FIELDS = ["subdomain", "vm_image", "ai_model"]
NUMBER_FIELDS = ["ram_reserve_mb", "disk_reserve_gb", "ram_allowance_mb", "disk_allowance_gb", "vm_max_running", "vm_cpu", "vm_ram_mb", "vm_disk_gb"]
HOSTILE_NUMBERS = ["12", "1; reboot", True, 1.5, [1], {"a": 1}, -1, 99_999_999_999_999_999, "<script>"]
NEW_KEYS = {"agent_version", "engine", "box", "agent_port", "ruvio"}


def _beat(token, root, **facts):
    body = copy.deepcopy(good_heartbeat())
    body["facts"].update(facts)
    reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)
    expect(reply.status == 204, f"heartbeat gave {reply.status}: {reply.raw[:150]!r}")


def _machine(operator, name="mini"):
    reply = operator.request("GET", f"/api/machines/{name}")
    expect(reply.status == 200, f"machine gave {reply.status}")
    return reply.body


def _patch(operator, body, name="mini", **kwargs):
    return operator.write("PATCH", f"/api/machines/{name}/settings", body, **kwargs)


def check_a_machine_that_has_not_reported_says_null_for_everything_new():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        machine = _machine(operator)
        expect(NEW_KEYS <= set(machine), f"missing keys: {NEW_KEYS - set(machine)}")
        expect(all(machine[key] is None for key in NEW_KEYS), f"nothing was reported, so nothing may be made up: { {k: machine[k] for k in NEW_KEYS} }")


def check_what_the_helper_reports_is_shown_and_an_old_helper_leaves_nulls():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        _beat(token, root)
        old = _machine(operator)
        expect(old["agent_version"] is None and old["engine"] is None, f"an old helper reported nothing: {old['agent_version']!r} {old['engine']!r}")
        expect(old["ruvio"] == {"installed": "1.0.0", "pinned": None, "state": "on"}, f"ruvio: {old['ruvio']}")
        _beat(token, root, agent_version="0.2.0", engine={"name": "incus", "version": None, "ready": False})
        new = _machine(operator)
        expect(new["agent_version"] == "0.2.0" and new["engine"] == {"name": "incus", "version": None, "ready": False}, f"{new['agent_version']!r} {new['engine']!r}")
        _beat(token, root)
        again = _machine(operator)
        expect(again["agent_version"] is None and again["engine"] is None, "a heartbeat that stopped saying it left the old answer standing")


def check_box_and_port_are_null_for_a_machine_the_parent_did_not_install_over_ssh():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        _beat(token, root)
        machine = _machine(operator)
        expect(machine["box"] is None and machine["agent_port"] is None, f"box/port: {machine['box']!r} {machine['agent_port']!r}")


def check_hostile_helper_version_and_engine_text_is_refused():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, "mini")
        for text in HOSTILE:
            if text == "":
                continue
            for label, facts in (("agent_version", {"agent_version": text}), ("engine name", {"engine": {"name": text, "version": None, "ready": True}}),
                                 ("engine version", {"engine": {"name": "incus", "version": text, "ready": True}})):
                body = copy.deepcopy(good_heartbeat())
                body["facts"].update(facts)
                reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)
                expect(reply.status == 400, f"{label} {text[:20]!r}: wanted 400, got {reply.status}")
        for label, facts in (("agent_version number", {"agent_version": 5}), ("engine list", {"engine": ["incus"]}), ("engine ready text", {"engine": {"name": "incus", "version": None, "ready": "yes"}}),
                             ("engine extra key", {"engine": {"name": "incus", "version": None, "ready": True, "path": "/bin/sh"}}), ("engine no ready", {"engine": {"name": "incus"}})):
            body = copy.deepcopy(good_heartbeat())
            body["facts"].update(facts)
            expect(Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None).status == 400, f"{label} was accepted")
        expect(_machine(operator)["last_seen"] is None, "a refused heartbeat updated the machine")


def check_settings_can_be_changed_after_the_machine_was_added_and_the_answer_is_the_machine():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        reply = _patch(operator, {"labels": ["office", "gpu"], "notes": "under the desk", "allow_gpu": False, "ram_reserve_mb": 4096, "ram_allowance_mb": 65536, "vm_max_running": 3,
                                  "vm_cpu": 4, "vm_ram_mb": 8192, "vm_disk_gb": 60, "vm_image": "images:ubuntu/24.04", "subdomain": "mini", "ai_model": "anthropic/claude-sonnet-5"})
        expect(reply.status == 200 and NEW_KEYS <= set(reply.body), f"patch gave {reply.status}: {reply.raw[:200]!r}")
        settings = _machine(operator)["settings"]
        expect(settings["labels"] == ["office", "gpu"] and settings["allow_gpu"] is False and settings["vm_cpu"] == 4 and settings["vm_image"] == "images:ubuntu/24.04", f"settings: {settings}")
        expect(settings["profile"] == "custom" and settings["public_chat"] is False, "fields outside the allow-list changed")
        cleared = _patch(operator, {"vm_image": None, "ram_reserve_mb": None}).body["settings"]
        expect(cleared.get("vm_image") is None and cleared.get("ram_reserve_mb") is None and cleared["vm_cpu"] == 4, f"clearing: {cleared}")


def check_a_change_can_rename_the_machine_but_not_to_another_machines_name():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        enrolled_machine(operator, "dgx")
        expect(_patch(operator, {"name": "studio"}).status == 200 and _machine(operator)["name"] == "studio", "the rename did not happen")
        expect(_machine(operator)["id"] == "mini", "the id changed")
        clash = _patch(operator, {"name": "dgx"})
        expect(clash.status == 409 and clash.body["error"]["code"] == "machine_exists", f"clash: {clash.status} {clash.raw[:100]!r}")
        expect(_machine(operator)["name"] == "studio", "a refused rename changed the name")


LEGAL_DISPLAY_NAMES = ["Mac Studio", "Luca's PC (RTX)", "R&D box_2.0", "Ünïcode Café"]
REFUSED_DISPLAY_NAMES = ["a b\"c';rm -rf ~;", "<b>x</b>", "$(reboot)", "`id`", "../../etc/passwd", "line\nbreak", "nul\u0000byte", " lead", "trail ", "two  spaces", "x" * 49, "", "{@html x}", "😀"]


def check_a_machine_can_be_given_a_name_with_spaces_capitals_and_marks_and_keeps_its_id():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        for name in LEGAL_DISPLAY_NAMES:
            expect(_patch(operator, {"name": name}).status == 200, f"{name!r} was refused")
            machine = _machine(operator)
            expect(machine["name"] == name and machine["id"] == "mini", f"name {machine['name']!r} id {machine['id']!r}")
            listed = operator.request("GET", "/api/machines").body["machines"]
            expect(any(m["name"] == name and m["id"] == "mini" for m in listed), "the list did not show the new name")


def check_a_display_name_that_differs_only_in_capitals_is_a_clash_and_a_hostile_one_is_refused():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        enrolled_machine(operator, "dgx")
        expect(_patch(operator, {"name": "Mac Studio"}).status == 200, "the first rename failed")
        clash = _patch(operator, {"name": "mac STUDIO"}, name="dgx")
        expect(clash.status == 409 and clash.body["error"]["code"] == "machine_exists", f"clash: {clash.status} {clash.raw[:100]!r}")
        expect(clash.body["error"]["message"] == "another machine already has that name", f"words: {clash.raw[:120]!r}")
        expect(_patch(operator, {"name": "mac studio"}).status == 200, "a machine may change the capitals of its own name")
        for text in REFUSED_DISPLAY_NAMES:
            expect(_patch(operator, {"name": text}).status == 400, f"{text[:20]!r} was accepted")
        expect(_machine(operator)["name"] == "mac studio" and _machine(operator, "dgx")["name"] == "dgx", "a refused rename changed a name")


def check_a_new_machine_cannot_be_invited_under_a_display_name_in_other_capitals():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        _patch(operator, {"name": "Studio"})
        invite = operator.write("POST", "/api/enrollments", {"name": "studio"})
        expect(invite.status == 409, f"invite for a taken display name gave {invite.status}")


def check_a_rename_is_audited_by_id_and_the_display_name_never_reaches_the_log():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        _patch(operator, {"name": "Luca's PC (RTX)"})
        entries = operator.request("GET", "/api/audit").body["entries"]
        change = next((e for e in entries if e["action"] == "machine.settings"), None)
        expect(change is not None and change["target"] == "mini", f"audit: {[(e['action'], e['target']) for e in entries]}")
        expect("Luca" not in json.dumps(entries), "the display name reached the audit log")


def check_hostile_text_in_every_text_field_is_refused_and_changes_nothing():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        before = _machine(operator)
        for field in TEXT_FIELDS:
            for text in HOSTILE:
                reply = _patch(operator, {field: text})
                expect(reply.status == 400, f"{field} {text[:20]!r}: wanted 400, got {reply.status}")
        for text in HOSTILE:
            expect(_patch(operator, {"labels": [text]}).status == 400, f"label {text[:20]!r} was accepted")
        expect(_machine(operator) == before, "a refused change altered the machine")


def check_hostile_notes_are_kept_as_plain_text_and_too_long_notes_are_refused():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        for text in (t for t in HOSTILE if len(t) <= 300):
            expect(_patch(operator, {"notes": text}).status == 200, f"notes {text[:20]!r} were refused")
            expect(_machine(operator)["settings"]["notes"] == text, "the notes were changed on the way")
        expect(_patch(operator, {"notes": "x" * 301}).status == 400, "notes over the limit were accepted")
        reply = operator.request("GET", "/api/machines/mini")
        expect((reply.header("Content-Type") or "").startswith("application/json") and reply.header("X-Content-Type-Options") == "nosniff", "machine data is not safe JSON")


def check_hostile_values_in_every_number_and_flag_field_are_refused():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        before = _machine(operator)
        for field in NUMBER_FIELDS:
            for value in HOSTILE_NUMBERS:
                expect(_patch(operator, {field: value}).status == 400, f"{field} {value!r} was accepted")
        for value in ("no", 1, None, [True]):
            expect(_patch(operator, {"allow_gpu": value}).status == 400, f"allow_gpu {value!r} was accepted")
        for key in ("labels", "notes"):
            expect(_patch(operator, {key: None}).status == 400, f"{key} was cleared")
        expect(_machine(operator) == before, "a refused change altered the machine")


def check_fields_outside_the_allow_list_are_refused():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        for key in ("profile", "public_chat", "id", "ip", "bundle_version", "box", "agent_port", "agent_version", "token", "command", "path", "settings", "__proto__", "state"):
            reply = _patch(operator, {key: "x"})
            expect(reply.status == 400 and "unknown field" in reply.body["error"]["message"], f"{key}: {reply.status} {reply.raw[:120]!r}")
        for raw in (b"", b"{", b"null", b"[]", b'"text"', b"{}"):
            expect(operator.write("PATCH", "/api/machines/mini/settings", raw=raw).status == 400, f"body {raw!r} was accepted")
        expect(_patch(operator, {"ram_reserve_mb": 8192, "ram_allowance_mb": 4096}).status == 400, "a reserve above the allowance was accepted")
        _patch(operator, {"ram_allowance_mb": 8192})
        expect(_patch(operator, {"ram_reserve_mb": 8192}).status == 400, "a reserve not below the allowance already there was accepted")


def check_the_settings_route_has_the_same_guards_as_every_operator_write():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        body = {"notes": "x"}
        expect(Browser(root, auto_login=False).request("PATCH", "/api/machines/mini/settings", body).status == 401, "no session was accepted")
        expect(operator.request("PATCH", "/api/machines/mini/settings", body).status == 403, "a change without the CSRF header was accepted")
        expect(_patch(operator, body, origin="https://evil.example").status == 403, "a foreign Origin was accepted")
        expect(_patch(operator, body, origin=None).status == 403, "a change with no Origin was accepted")
        expect(_patch(operator, body, headers={"Host": "evil.example"}).status == 403, "a foreign Host was accepted")
        expect(_patch(operator, body, name="ghost").status == 404, "an unknown machine was not a 404")
        for bad in ("..%2Fx", "UPPER", "a%20b", "x" * 64):
            expect(_patch(operator, body, name=bad).status == 404, f"id {bad!r} was not a 404")
        expect(operator.write("PATCH", "/api/machines/mini/settings", raw=json.dumps({"notes": "x" * 70_000}).encode()).status in (400, 413), "a huge body was accepted")
        expect(_machine(operator)["settings"] is None or _machine(operator)["settings"]["notes"] != "x", "a refused change was applied")


def check_a_change_is_audited_by_field_name_and_never_by_value():
    with running() as root:
        operator = Browser(root)
        enrolled_machine(operator, "mini")
        secret_looking = "sk-ant-api03-THIS-LOOKS-LIKE-A-SECRET"
        _patch(operator, {"notes": secret_looking, "vm_cpu": 2})
        entries = operator.request("GET", "/api/audit").body["entries"]
        change = next((e for e in entries if e["action"] == "machine.settings"), None)
        expect(change is not None and change["target"] == "mini", f"no audit entry: {[e['action'] for e in entries]}")
        expect(json.loads(change["detail"]) == {"fields": "notes,vm_cpu"}, f"detail: {change['detail']}")
        expect(secret_looking not in json.dumps(entries), "a value reached the audit log")


CHECKS = [
    check_a_machine_that_has_not_reported_says_null_for_everything_new, check_what_the_helper_reports_is_shown_and_an_old_helper_leaves_nulls,
    check_box_and_port_are_null_for_a_machine_the_parent_did_not_install_over_ssh, check_hostile_helper_version_and_engine_text_is_refused,
    check_settings_can_be_changed_after_the_machine_was_added_and_the_answer_is_the_machine, check_a_change_can_rename_the_machine_but_not_to_another_machines_name,
    check_hostile_text_in_every_text_field_is_refused_and_changes_nothing, check_hostile_notes_are_kept_as_plain_text_and_too_long_notes_are_refused,
    check_hostile_values_in_every_number_and_flag_field_are_refused, check_fields_outside_the_allow_list_are_refused,
    check_the_settings_route_has_the_same_guards_as_every_operator_write, check_a_change_is_audited_by_field_name_and_never_by_value,
    check_a_machine_can_be_given_a_name_with_spaces_capitals_and_marks_and_keeps_its_id, check_a_display_name_that_differs_only_in_capitals_is_a_clash_and_a_hostile_one_is_refused,
    check_a_new_machine_cannot_be_invited_under_a_display_name_in_other_capitals, check_a_rename_is_audited_by_id_and_the_display_name_never_reaches_the_log,
]
