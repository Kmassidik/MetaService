"""The chat bundle through the Root: registry, pin, install, upgrade, rollback, chat links, and where the access key may live."""
import http.client
import json
import os

from contract.agent_tests.support import wait_for
from contract.root_tests.support import Browser, expect
from contract.system_tests.support import world

V1, V2 = "0.1.0", "0.2.0"


def chat_call(url, key, message="hello"):
    host, port = url.split("//")[1].split("/")[0].split(":")
    connection = http.client.HTTPConnection(host, int(port), timeout=10)
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    connection.request("POST", "/api/chat", json.dumps({"message": message}), headers)
    reply = connection.getresponse()
    return reply.status, reply.read()


def pin(w, version):
    return w.operator.write("POST", "/api/bundles/pin", {"version": version})


def install(w, machine, workload=None):
    reply = w.operator.write("POST", f"/api/machines/{machine}/bundle/install", {"workload": workload} if workload else {})
    expect(reply.status == 202, f"install gave {reply.status}: {reply.raw[:200]!r}")
    return w.wait_command(reply.body["command"]["id"], seconds=40)


def link(w, machine, workload=None):
    suffix = f"&workload={workload}" if workload else ""
    return w.operator.request("GET", f"/api/chat-link?machine={machine}{suffix}")


def check_the_registry_lists_the_files_and_an_install_needs_a_pin_first():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        overview = w.operator.request("GET", "/api/bundles").body
        expect([b["version"] for b in overview["bundles"]] == [V2, V1] and overview["pinned"] is None, f"overview: {overview}")
        expect(all(len(b["sha256"]) == 64 for b in overview["bundles"]), "a checksum is missing")
        reply = w.operator.write("POST", "/api/machines/mini/bundle/install", {})
        expect(reply.status == 409 and reply.body["error"]["code"] == "no_bundle_pinned", f"{reply.status} {reply.body}")


def check_pin_install_open_and_the_key_stays_out_of_the_command_and_the_database():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        expect(pin(w, V1).status == 200, "pin failed")
        done = install(w, "mini")
        expect(done["result"]["version"] == V1 and "chat_key" not in done["result"], f"result: {done['result']}")
        wait_for(lambda: w.view("mini")["bundle_version"] == V1, 15, "the Root never saw the bundle version")
        opened = link(w, "mini")
        expect(opened.status == 200 and "#k=" in opened.body["url"], f"link: {opened.status} {opened.body}")
        url, key = opened.body["url"].split("#k=")
        expect(chat_call(url, key)[0] == 200, "the chat did not answer with its key")
        expect(chat_call(url, None)[0] == 401 and chat_call(url, key + "x")[0] == 401, "the chat answered without the right key")
        raw = b"".join(open(os.path.join(w.root.dir, n), "rb").read() for n in os.listdir(w.root.dir) if n.startswith("root.sqlite3"))
        expect(key.encode() not in raw, "the chat key is in the Root's database in clear")
        expect(key not in w.operator.request("GET", "/api/commands").raw.decode(), "the chat key is in a command record")
        audit = [e["action"] for e in w.operator.request("GET", "/api/audit").body["entries"]]
        expect("bundle.pin" in audit and "bundle.install" in audit and "chat.link" in audit, f"audit: {audit[:10]}")


def check_a_new_pin_upgrades_what_has_the_bundle_and_a_rollback_undoes_it():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        pin(w, V1)
        install(w, "mini")
        wait_for(lambda: w.view("mini")["bundle_version"] == V1, 15, "no version")
        pin(w, V2)
        wait_for(lambda: w.view("mini")["bundle_version"] == V2, 40, "the machine was not upgraded to the new pin")
        reply = w.operator.write("POST", "/api/bundles/rollback")
        expect(reply.status == 200 and reply.body["pinned"] == V1, f"rollback: {reply.status} {reply.body}")
        wait_for(lambda: w.view("mini")["bundle_version"] == V1, 40, "the machine was not rolled back")
        expect(chat_call(*(lambda u: (u[0], u[1]))(link(w, "mini").body["url"].split("#k=")))[0] == 200, "the chat does not answer after the rollback")


def check_pins_and_rollbacks_refuse_bad_requests():
    with world(with_bundles=True) as w:
        w.add_machine("mini")
        expect(w.operator.write("POST", "/api/bundles/rollback").status == 409, "a rollback with nothing before it was accepted")
        expect(pin(w, "9.9.9").status == 404, "an unknown version was pinned")
        for bad in ("1.2", "x", "1.2.3; reboot", "../1.0.0", ""):
            expect(pin(w, bad).status == 400, f"pin {bad!r} was accepted")
        stranger = Browser(w.root)
        expect(stranger.request("GET", "/api/bundles").status == 401, "the registry is open without a session")
        expect(w.operator.request("POST", "/api/bundles/pin", {"version": V1}).status == 403, "a pin without CSRF was accepted")
        expect(w.operator.request("POST", "/api/machines/mini/bundle/install", {}).status == 403, "an install without CSRF was accepted")
        expect(link(w, "mini").status == 404 and link(w, "ghost").status == 404 and w.operator.request("GET", "/api/chat-link?machine=..%2Fx").status == 404, "chat links for unknown targets")
        expect(stranger.request("GET", "/api/chat-link?machine=mini").status == 401, "chat links are open without a session")


def check_agents_download_only_registered_bundles_with_their_machine_token():
    with world(with_bundles=True) as w:
        mini = w.add_machine("mini")
        anon = Browser(w.root)
        expect(anon.request("GET", f"/v1/bundles/{V1}/noarch", origin=None).status == 401, "a download without a token worked")
        good = anon.request("GET", f"/v1/bundles/{V1}/noarch", headers={"Authorization": f"Bearer {mini.machine_token}"}, origin=None)
        expect(good.status == 200 and len(good.raw) > 1000 and good.header("X-Bundle-Sha256") == w.bundles.sha[V1], f"download: {good.status}")
        for path in (f"/v1/bundles/9.9.9/noarch", f"/v1/bundles/{V1}/windows-x86", f"/v1/bundles/..%2Fx/noarch", f"/v1/bundles/{V1}/..%2Fx"):
            expect(anon.request("GET", path, headers={"Authorization": f"Bearer {mini.machine_token}"}, origin=None).status == 404, f"{path} was not a 404")
        as_command = anon.request("GET", f"/v1/bundles/{V1}/noarch", headers={"Authorization": f"Bearer {mini.command_token}"}, origin=None)
        expect(as_command.status == 401, "the command token downloaded a bundle")


def check_a_workload_gets_the_bundle_through_copy_and_exec_with_no_key_in_the_arguments():
    with world(with_bundles=True) as w:
        mini = w.add_machine("mini", engine="apple")
        _, workload = w.make(name="box")
        pin(w, V1)
        install(w, "mini", workload)
        wait_for(lambda: w.view("mini")["workloads"][0]["bundle_version"] == V1, 15, "the workload never showed the bundle")
        calls = mini.container.calls()
        copies = [c for c in calls if c[0] == "cp"]
        runs = [c for c in calls if c[0] == "exec"]
        expect(len(copies) == 2 and len(runs) == 1, f"calls: {[c[0] for c in calls]}")
        expect(runs[0][:3] == ["exec", "-e", "MS_PORT=" + runs[0][2].split("=")[1]] and "MS_VERSION=" + V1 in runs[0], f"exec call: {runs[0][:6]}")
        opened = link(w, "mini", workload)
        expect(opened.status == 200, f"workload link: {opened.status}")
        key = opened.body["url"].split("#k=")[1]
        expect(all(key not in " ".join(c) for c in calls), "the chat key is in a command-line argument")


CHECKS = [
    check_the_registry_lists_the_files_and_an_install_needs_a_pin_first,
    check_pin_install_open_and_the_key_stays_out_of_the_command_and_the_database,
    check_a_new_pin_upgrades_what_has_the_bundle_and_a_rollback_undoes_it,
    check_pins_and_rollbacks_refuse_bad_requests,
    check_agents_download_only_registered_bundles_with_their_machine_token,
    check_a_workload_gets_the_bundle_through_copy_and_exec_with_no_key_in_the_arguments,
]
