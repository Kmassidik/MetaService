"""Ruvio (the chat) on and off per machine, through the Root: what the machine page reads, the turn-off route, and the parent pinning the only chat it has."""
import os
import time

from contract.agent_tests.support import wait_for
from contract.root_tests.support import Browser, expect
from contract.system_tests.checks_bundles import chat_call, install, link, pin
from contract.system_tests.support import world

BUILT = "0.4.0"
FLAVORS = ["swift", "rust"]
SETTLE_SECONDS = 12
HOSTILE = ["'; DROP TABLE x;--", "<script>alert(1)</script>", "$(reboot)", "`id`", "../../etc/passwd", "a b", "A" * 70, "--privileged", "", "line\nbreak"]


def ruvio(w, name):
    return w.view(name)["ruvio"]


def uninstall(w, machine, workload=None):
    reply = w.operator.write("POST", f"/api/machines/{machine}/bundle/uninstall", {"workload": workload} if workload else {})
    expect(reply.status == 202, f"uninstall gave {reply.status}: {reply.raw[:200]!r}")
    return w.wait_command(reply.body["command"]["id"], seconds=40)


def audit_actions(w):
    return [(e["action"], e["actor"], e["target"]) for e in w.operator.request("GET", "/api/audit").body["entries"]]


def chat_answers(url, key):
    try:
        return chat_call(url, key)[0] == 200
    except OSError:
        return False


def check_with_one_chat_built_the_parent_pins_it_and_the_page_reads_the_helper_and_engine():
    with world(with_bundles=True, bundle_versions=[BUILT]) as w:
        machines = {flavor: w.add_machine(f"m-{flavor}", flavor=flavor) for flavor in FLAVORS}
        expect(w.operator.request("GET", "/api/bundles").body["pinned"] == BUILT, "the only built chat was not pinned")
        expect(("bundle.autopin", "root", BUILT) in audit_actions(w), f"the pin was not written to the audit log: {audit_actions(w)[:6]}")
        for flavor, machine in machines.items():
            view, health = w.view(machine.name), machine.agent.call("GET", "/v1/health")[1]
            expect(view["agent_version"] == health["agent_version"], f"{flavor}: page says {view['agent_version']!r}, the helper says {health['agent_version']!r}")
            expect(view["engine"] == {"name": "simulated", "version": None, "ready": True}, f"{flavor}: engine {view['engine']}")
            expect(view["ruvio"] == {"installed": None, "pinned": BUILT, "state": "off"}, f"{flavor}: ruvio {view['ruvio']}")
            expect(view["box"] is None and view["agent_port"] is None, f"{flavor}: box/port are only known for a machine installed over SSH")


def check_with_no_chat_built_the_page_says_so_and_turning_it_on_is_refused_cleanly():
    with world(with_bundles=True, bundle_versions=[]) as w:
        w.add_machine("mini")
        expect(ruvio(w, "mini") == {"installed": None, "pinned": None, "state": "unavailable"}, f"ruvio: {ruvio(w, 'mini')}")
        reply = w.operator.write("POST", "/api/machines/mini/bundle/install", {})
        expect(reply.status == 409 and reply.body["error"] == {"code": "no_chat_built", "message": "no chat is built on the parent"}, f"{reply.status} {reply.body}")
        expect(not any(action == "bundle.autopin" for action, _, _ in audit_actions(w)), "something was pinned that does not exist")
        expect(w.operator.request("GET", "/api/commands").body["commands"] == [], "a refused install left a command behind")


def check_with_two_chats_built_nothing_is_pinned_for_the_person():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        expect(ruvio(w, "mini") == {"installed": None, "pinned": None, "state": "unavailable"}, f"ruvio: {ruvio(w, 'mini')}")
        reply = w.operator.write("POST", "/api/machines/mini/bundle/install", {})
        expect(reply.status == 409 and reply.body["error"]["code"] == "no_bundle_pinned", f"{reply.status} {reply.body}")
        expect(not any(action == "bundle.autopin" for action, _, _ in audit_actions(w)), "the parent chose between two chats by itself")


def check_ruvio_off_stops_the_chat_keeps_its_data_and_on_again_brings_it_back_with_the_same_key():
    for flavor in FLAVORS:
        with world(with_bundles=True, bundle_versions=[BUILT]) as w:
            machine = w.add_machine("mini", flavor=flavor)
            install(w, "mini")
            wait_for(lambda: ruvio(w, "mini")["state"] == "on", 20, f"{flavor}: the page never said on")
            url, key = link(w, "mini").body["url"].split("#k=")
            expect(chat_answers(url, key), f"{flavor}: the chat did not answer")
            data = os.path.join(machine.agent.state, "chat-data")
            expect(os.path.isdir(data) and os.listdir(data), f"{flavor}: the chat made no data folder")
            before = sorted(os.listdir(data))
            done = uninstall(w, "mini")
            expect(done["type"] == "bundle_uninstall", f"{flavor}: command {done}")
            wait_for(lambda: ruvio(w, "mini") == {"installed": None, "pinned": BUILT, "state": "off"}, 20, f"{flavor}: the page never said off: {ruvio(w, 'mini')}")
            wait_for(lambda: not chat_answers(url, key), 10, f"{flavor}: the chat kept answering after it was turned off")
            expect(sorted(os.listdir(data)) == before, f"{flavor}: the chat data folder changed when the chat was turned off")
            time.sleep(SETTLE_SECONDS)
            kinds = [c["type"] for c in w.operator.request("GET", "/api/commands").body["commands"]]
            expect(kinds.count("bundle_install") == 1 and ruvio(w, "mini")["state"] == "off", f"{flavor}: the parent put the chat back by itself: {kinds}")
            install(w, "mini")
            wait_for(lambda: ruvio(w, "mini")["state"] == "on", 20, f"{flavor}: the page never said on again")
            again_url, again_key = link(w, "mini").body["url"].split("#k=")
            expect(again_key == key and chat_answers(again_url, again_key), f"{flavor}: the chat did not come back with its key")
            expect(set(before) <= set(os.listdir(data)), f"{flavor}: data was lost")
            actions = [action for action, _, _ in audit_actions(w)]
            expect("bundle.uninstall" in actions and "workload.bundle_uninstall_succeeded" in actions, f"audit: {actions[:10]}")


def check_ruvio_off_in_a_workload_leaves_the_machines_chat_alone():
    with world(with_bundles=True, bundle_versions=[BUILT]) as w:
        mini = w.add_machine("mini", engine="apple")
        _, workload = w.make(name="box")
        install(w, "mini")
        install(w, "mini", workload)
        wait_for(lambda: w.view("mini")["workloads"][0]["bundle_version"] == BUILT and ruvio(w, "mini")["state"] == "on", 20, "both chats never showed")
        uninstall(w, "mini", workload)
        wait_for(lambda: w.view("mini")["workloads"][0]["bundle_version"] is None, 20, "the workload still shows the chat")
        expect(ruvio(w, "mini")["state"] == "on", "turning the chat off in a workload turned it off on the machine")
        runs = [c[-1] for c in mini.container.calls() if c[0] == "exec" and "disable --now" in c[-1]]
        expect(len(runs) == 1 and "chat-data" not in runs[0] and "rm -rf" not in runs[0], f"the workload's uninstall script: {runs}")


def check_turning_ruvio_off_refuses_what_makes_no_sense():
    with world(with_bundles=True, bundle_versions=[BUILT]) as w:
        w.add_machine("mini", engine="apple")
        _, workload = w.make(name="box")
        post = lambda machine, body, **kw: w.operator.write("POST", f"/api/machines/{machine}/bundle/uninstall", body, **kw)  # noqa: E731
        reply = post("mini", {})
        expect(reply.status == 409 and reply.body["error"]["code"] == "chat_not_installed", f"nothing installed: {reply.status} {reply.body}")
        expect(post("mini", {"workload": workload}).status == 409, "a workload without the chat was accepted")
        expect(post("ghost", {}).status == 404 and post("mini", {"workload": "ghost"}).status == 404, "unknown machine or workload was not a 404")
        for text in HOSTILE:
            expect(post("mini", {"workload": text}).status == 400, f"workload {text[:20]!r} was accepted")
        for raw in (b"{", b"[]", b'{"surprise":1}', b'{"workload": 5}'):
            expect(w.operator.write("POST", "/api/machines/mini/bundle/uninstall", raw=raw).status == 400, f"body {raw!r} was accepted")
        for bad in ("..%2Fx", "UPPER", "a%20b"):
            expect(post(bad, {}).status == 404, f"machine {bad!r} was not a 404")
        expect(w.operator.request("POST", "/api/machines/mini/bundle/uninstall", {}).status == 403, "an uninstall without CSRF was accepted")
        expect(post("mini", {}, origin="https://evil.example").status == 403, "a foreign Origin was accepted")
        expect(Browser(w.root, auto_login=False).request("POST", "/api/machines/mini/bundle/uninstall", {}).status == 401, "an uninstall without a session was accepted")
        expect(not any(c[0] == "exec" for c in w.machines["mini"].container.calls()), "a refused request reached the machine")


def check_a_pin_the_person_made_is_never_replaced_by_the_parent():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        expect(pin(w, "0.1.0").status == 200, "pin failed")
        expect(w.operator.request("GET", "/api/bundles").body["pinned"] == "0.1.0", "the pin is wrong")
        expect(not any(action == "bundle.autopin" for action, _, _ in audit_actions(w)), "the parent pinned by itself over the person's choice")


CHECKS = [
    check_with_one_chat_built_the_parent_pins_it_and_the_page_reads_the_helper_and_engine, check_with_no_chat_built_the_page_says_so_and_turning_it_on_is_refused_cleanly,
    check_with_two_chats_built_nothing_is_pinned_for_the_person, check_ruvio_off_stops_the_chat_keeps_its_data_and_on_again_brings_it_back_with_the_same_key,
    check_ruvio_off_in_a_workload_leaves_the_machines_chat_alone, check_turning_ruvio_off_refuses_what_makes_no_sense, check_a_pin_the_person_made_is_never_replaced_by_the_parent,
]
