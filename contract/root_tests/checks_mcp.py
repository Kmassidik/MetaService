"""The MCP endpoint of the parent (mcp/SPEC.md sections 2, 3, 4 and 7), against a real Root and a fake helper (agent/fake): who is let in (401 for no, bad, revoked and
expired tokens), the protocol (negotiation, 405, the Origin rule, batches, errors), the nine tools on their happy path, the operator API of the panel, that a token is
shown once, and that no token text or key reaches an answer or the audit trail. The policy (scopes, quotas, approvals, idempotency, machine choice) is in checks_mcp_policy.py."""
import json

from agent.fake.engine import MachineSpec
from contract.root_tests.mcp_support import FAKE_TOKEN_TEXT, SSH_KEY, Client, client_for, everything_said, make_person, make_token, parent, sql, wait_until, workload_of
from contract.root_tests.support import Browser, expect

TOOLS = ["list_machines", "machine_capacity", "list_vms", "vm_status", "create_vm", "start_vm", "stop_vm", "delete_vm", "get_request"]
VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]


def check_mcp_with_no_tokens_everything_is_401_with_the_challenge():
    with parent() as (root, operator, machines):
        expect(operator.request("GET", "/api/mcp/tokens").body["tokens"] == [], "there must be no default token")
        for client in [Client(root, None), Client(root, FAKE_TOKEN_TEXT), Client(root, "not-a-token"), Client(root, "msk_short")]:
            reply = client.rpc("tools/list")
            expect(reply.status == 401, f"{client.token!r}: {reply.status}")
            expect(reply.header("WWW-Authenticate") == 'Bearer realm="metaservice"', f"challenge: {reply.header('WWW-Authenticate')}")
            expect(reply.body["error"]["code"] == "unauthorized", reply.raw)
        expect(Client(root, FAKE_TOKEN_TEXT).post(raw=b"{}").status == 401, "a body must not be read before the token is")


def check_mcp_a_revoked_or_expired_token_is_401_and_a_good_one_works():
    with parent() as (root, operator, machines):
        revoked, revoked_text, info = client_for(root, operator, "old")
        expect(revoked.rpc("ping").status == 200, "a good token must work")
        gone = operator.write("DELETE", f"/api/mcp/tokens/{info['id']}")
        expect(gone.status == 200 and gone.body["info"]["status"] == "revoked", gone.raw)
        expect(operator.write("DELETE", f"/api/mcp/tokens/{info['id']}").status == 200, "revoking twice must not fail")
        expect(revoked.rpc("ping").status == 401, "a revoked token must be refused at once")
        expect(operator.write("DELETE", "/api/mcp/tokens/nope-123").status == 404, "an unknown token id is 404")
        old, old_text, old_info = client_for(root, operator, "stale")
        sql(root, "UPDATE api_tokens SET expires_at = 1 WHERE id = ?", old_info["id"])
        expect(old.rpc("ping").status == 401, "an expired token must be refused")
        listed = {row["name"]: row for row in operator.request("GET", "/api/mcp/tokens").body["tokens"]}
        expect(listed["old-token"]["status"] == "revoked" and listed["stale-token"]["status"] == "expired", f"{listed}")


def check_mcp_bad_tokens_from_one_address_are_locked_out_for_a_while():
    with parent() as (root, operator, machines):
        good, _, _ = client_for(root, operator)
        statuses = [Client(root, FAKE_TOKEN_TEXT).rpc("ping").status for _ in range(12)]
        expect(statuses[:10] == [401] * 10 and statuses[10:] == [429, 429], f"{statuses}")
        expect(good.rpc("ping").status == 429, "the lockout is for the address")


def check_mcp_initialize_negotiates_the_version_and_the_small_methods_work():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator)
        for asked in VERSIONS:
            result = client.rpc("initialize", {"protocolVersion": asked, "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}}).body["result"]
            expect(result["protocolVersion"] == asked, f"{asked}: {result}")
            expect(result["capabilities"] == {"tools": {}} and result["serverInfo"]["name"] == "metaservice", f"{result}")
        expect(client.rpc("initialize", {"protocolVersion": "1999-01-01"}).body["result"]["protocolVersion"] == "2025-06-18", "an unknown version gets the newest")
        expect(client.rpc("initialize", {}).body["result"]["protocolVersion"] == "2025-06-18", "no version gets the newest")
        note = client.post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        expect(note.status == 202 and note.raw == b"", f"{note.status} {note.raw!r}")
        expect(client.rpc("ping").body["result"] == {}, "ping")
        missing = client.rpc("resources/list")
        expect(missing.status == 200 and missing.body["error"]["code"] == -32601, missing.raw)


def check_mcp_malformed_messages_get_the_json_rpc_errors():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator)
        cases = [(b"{nope", -32700), (b"", -32700), (b"[]", -32600), (json.dumps([{"jsonrpc": "2.0", "id": 1, "method": "ping"}]).encode(), -32600), (b'"x"', -32600),
                 (b'{"jsonrpc":"1.0","id":1,"method":"ping"}', -32600), (b'{"jsonrpc":"2.0","id":1}', -32600), (b'{"jsonrpc":"2.0","id":1,"method":"ping","params":[1]}', -32602),
                 (b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}', -32602), (b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"rm_rf"}}', -32602),
                 (b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_vms","arguments":[1]}}', -32602)]
        for raw, code in cases:
            reply = client.post(raw=raw)
            expect(reply.status == 200 and reply.body["error"]["code"] == code, f"{raw!r}: {reply.status} {reply.raw[:200]!r}")
        batch = client.post(raw=json.dumps([{"jsonrpc": "2.0", "id": 1, "method": "ping"}]).encode())
        expect("batches" in batch.body["error"]["message"], "a batch is refused in words")
        big = client.post(raw=b'{"jsonrpc":"2.0","id":1,"method":"ping","params":{"x":"' + b"a" * 70000 + b'"}}')
        expect(big.status == 413, f"a body over 64 KiB gave {big.status}")


def check_mcp_get_and_delete_are_405_and_the_origin_rule_holds():
    with parent() as (root, operator, machines):
        client, token, _ = client_for(root, operator)
        for method in ("GET", "DELETE"):
            reply = client.web.request(method, "/mcp", headers={"Authorization": f"Bearer {token}"}, origin=None, cookies=False)
            expect(reply.status == 405 and reply.header("Allow") == "POST", f"{method}: {reply.status}")
        expect(client.rpc("ping", origin=None).status == 200, "no Origin is a normal client")
        expect(client.rpc("ping", origin=root.base).status == 200, "the panel's own Origin is allowed")
        for origin in ("https://evil.example", "null", root.base + ".evil.example"):
            reply = client.rpc("ping", origin=origin)
            expect(reply.status == 403, f"Origin {origin}: {reply.status}")
        wrong_host = client.rpc("ping", headers={"Host": "evil.example"})
        expect(wrong_host.status == 403, f"a wrong Host gave {wrong_host.status}")


def check_mcp_tools_list_has_nine_tools_with_real_schemas_and_structured_content_by_version():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator)
        tools = client.rpc("tools/list").body["result"]["tools"]
        expect([tool["name"] for tool in tools] == TOOLS, [tool["name"] for tool in tools])
        for tool in tools:
            schema = tool["inputSchema"]
            expect(schema["type"] == "object" and schema["additionalProperties"] is False, f"{tool['name']}: {schema}")
            expect(set(schema["required"]) <= set(schema["properties"]), tool["name"])
            expect(tool["description"].endswith("."), tool["description"])
        expect("approve" not in " ".join(TOOLS), "no tool approves anything")
        newer = Client(root, client.token, "2025-06-18").tool("list_machines")
        older = Client(root, client.token, "2025-03-26").tool("list_machines")
        none = Client(root, client.token, None).tool("list_machines")
        expect("structuredContent" in newer.result and newer.result["structuredContent"] == newer.data, "2025-06-18 carries structuredContent")
        expect("structuredContent" not in older.result and "structuredContent" not in none.result, "older versions do not")


def check_mcp_the_tools_do_their_job_on_the_happy_path():
    with parent([("mini", MachineSpec(), False)]) as (root, operator, machines):
        machines["mini"].helper.make("operator-vm", kind="vm", gpu_mode="none")
        client, _, _ = client_for(root, operator, "claude", scopes=["read", "create", "destroy"])
        listed = client.tool("list_machines").ok()["machines"]
        expect(len(listed) == 1 and listed[0]["id"] == "mini" and listed[0]["shared"] is False and listed[0]["engine_ready"] is True and listed[0]["gpu"] is None, listed)
        capacity = client.tool("machine_capacity", {"machine": "mini"}).ok()
        expect(capacity["sizes_that_fit"] == ["small", "medium", "large"] and capacity["free_ram_mb"] > 40000 and capacity["gpu_free_gb"] is None, capacity)
        expect(client.tool("machine_capacity", {"machine": "nowhere"}).is_error, "an unknown machine is refused")
        made = client.tool("create_vm", {"machine": "mini", "name": "web", "size": "small", "ssh_public_key": SSH_KEY, "idempotency_key": "first"}).ok()
        vm = made["vm"]
        expect(made["status"] == "done" and vm["state"] == "running" and vm["name"] == "web" and vm["vcpu"] == 1 and vm["ram_mb"] == 2048 and vm["disk_gb"] == 20, made)
        expect(vm["machine"] == "mini" and vm["created_by_me"] is True and "ssh_command" in vm, vm)
        vms = client.tool("list_vms").ok()
        expect([row["name"] for row in vms["vms"]] == ["web"] and vms["others"] == 1, vms)
        expect(client.tool("list_vms", {"machine": "mini"}).ok()["vms"][0]["id"] == vm["id"], "list_vms by machine")
        status = client.tool("vm_status", {"machine": "mini", "vm": vm["id"]}).ok()
        expect(status["state"] == "running" and status["stopped_reason"] is None, status)
        for shown in (vm, vms["vms"][0], status):
            expect(shown["created_by"]["kind"] == "mcp" and shown["created_by"]["label"] == "claude (MCP)" and len(shown["created_by"]["fingerprint"]) == 8 and shown["created_by"]["intact"] is True, shown["created_by"])
        stopped = client.tool("stop_vm", {"machine": "mini", "vm": vm["id"]}).ok()
        expect(stopped["status"] == "done", stopped)
        wait_until(lambda: client.tool("vm_status", {"machine": "mini", "vm": vm["id"]}).data.get("state") == "stopped", what="the VM to show stopped")
        started = client.tool("start_vm", {"machine": "mini", "vm": vm["id"]}).ok()
        expect(started["status"] == "done" and started["vm"]["state"] == "running", started)
        followed = client.tool("get_request", {"request_id": made["request_id"]}).ok()
        expect(followed["status"] == "done" and followed["vm"]["id"] == vm["id"], followed)
        keys = wait_until(lambda: operator.request("GET", f"/api/machines/mini/workloads/{vm['id']}/ssh-keys").body["keys"], what="the public key to reach the VM")
        expect(len(keys) == 1 and keys[0]["type"] == "ssh-ed25519", keys)


def check_mcp_a_vm_that_takes_longer_than_the_wait_answers_creating_and_get_request_follows_it():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator)
        quick = client.tool("create_vm", {"size": "small", "wait_seconds": 0}).ok()
        expect(quick["status"] == "creating" and quick["request_id"], quick)
        done = wait_until(lambda: (lambda reply: reply if reply["status"] == "done" else None)(client.tool("get_request", {"request_id": quick["request_id"]}).ok()), what="the request to be done")
        expect(done["vm"]["state"] in ("running", "provisioning"), done)
        other, _, _ = client_for(root, operator, "other")
        expect(other.tool("get_request", {"request_id": quick["request_id"]}).error.startswith("There is no such request"), "a request is only for its own token")
        expect(client.tool("get_request", {"request_id": "mr-nothing"}).is_error, "an unknown request")


def check_mcp_bad_arguments_are_refused_in_words_that_name_the_field():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator)
        cases = [("create_vm", {}, "size is required"), ("create_vm", {"size": "huge"}, "size"), ("create_vm", {"size": "small", "wait_seconds": 99}, "wait_seconds"),
                 ("create_vm", {"size": "custom", "vcpu": 2}, "custom needs"), ("create_vm", {"size": "small", "vcpu": 2}, "only for size custom"),
                 ("create_vm", {"size": "small", "colour": "red"}, "unknown field colour"), ("create_vm", {"size": "small", "image": "nonsuch"}, "image"),
                 ("create_vm", {"size": "small", "ssh_public_key": "not a key"}, ""),
                 ("create_vm", {"size": "small", "machine": "Bad Name"}, "machine"), ("vm_status", {"machine": "mini"}, "machine and vm"), ("list_machines", {"x": 1}, "unknown field")]
        for name, arguments, words in cases:
            result = client.tool(name, arguments)
            expect(result.is_error and words in result.error, f"{name} {arguments}: {result.data}")
        expect(client.tool("list_vms").ok()["vms"] == [], "no refused call made a VM")


def check_mcp_the_panel_shows_the_token_once_and_nothing_secret_is_ever_said():
    with parent() as (root, operator, machines):
        person = make_person(operator, "Ayu", ["read", "create"], {"max_vms": 2})
        reply = operator.write("POST", "/api/mcp/tokens", {"name": "once", "person_id": person["id"], "scopes": ["read"], "expires_in_days": 30})
        text = reply.body["token"]
        expect(reply.status == 201 and text.startswith("msk_") and len(text) == 47, reply.raw)
        info = reply.body["info"]
        expect(info["prefix"] == text[4:12] and info["scopes"] == ["read"] and info["person_id"] == person["id"] and info["person_name"] == "Ayu", info)
        expect("quotas" not in info and "auto_approve" not in info, "quotas are the person's, and nothing is auto-approved any more")
        expect(text not in json.dumps(info), "the info row must not hold the token")
        full = Client(root, make_token(operator, person["id"], "full")[0])
        full.tool("create_vm", {"size": "small", "ssh_public_key": SSH_KEY, "idempotency_key": "k-1"})
        full.tool("list_machines")
        full.rpc("tools/call", {"name": "create_vm", "arguments": {"size": "bogus", "ssh_public_key": SSH_KEY}})
        said = everything_said(root, operator)
        expect(text not in said and full.token not in said, "a token text reached an answer or the audit trail")
        expect(SSH_KEY not in said and SSH_KEY.split()[1] not in said, "the public key must not be in the audit trail or the panel's answers")
        again = operator.request("GET", "/api/mcp/tokens")
        expect(all("token" not in row for row in again.body["tokens"]) and text not in again.raw.decode(), "the token is shown once")
        info_text = operator.request("GET", "/api/mcp/info")
        expect(info_text.body["endpoint"].endswith("/mcp") and info_text.body["tools"] == TOOLS and info_text.body["defaults"]["expires_in_days"] == 90, info_text.raw)
        expect("auto_approve" not in info_text.raw.decode(), "no approval wording is left")
        stored = " ".join(str(row) for row in sql(root, "SELECT * FROM api_tokens"))
        expect(text not in stored and full.token not in stored, "a token text is stored")
        reader = Client(root, text)
        expect(reader.tool("create_vm", {"size": "small"}).is_error, "the token's own scopes (read only) are the limit, though the person may create")


def check_mcp_the_operator_api_needs_a_session_and_the_csrf_header_and_checks_its_input():
    with parent() as (root, operator, machines):
        anonymous = Browser(root, auto_login=False)
        for method, path in [("GET", "/api/mcp/info"), ("GET", "/api/mcp/tokens"), ("GET", "/api/mcp/people"), ("GET", "/api/mcp/activity")]:
            expect(anonymous.request(method, path).status == 401, f"{path} without a session")
        expect(operator.request("GET", "/api/mcp/approvals").status == 404, "approvals are gone")
        person = make_person(operator, "Ayu")
        expect(operator.request("POST", "/api/mcp/tokens", {"name": "x", "person_id": person["id"]}).status == 403, "a write without the CSRF header")
        expect(operator.write("POST", "/api/mcp/tokens", {"name": "x", "person_id": person["id"]}, origin="https://evil.example").status == 403, "a write from another origin")
        expect(operator.request("POST", "/api/mcp/people", {"name": "Zed"}).status == 403, "a person without the CSRF header")
        pid = person["id"]
        bad = [{}, {"name": "a"}, {"person_id": pid}, {"name": "", "person_id": pid}, {"name": "a" * 41, "person_id": pid}, {"name": "<script>", "person_id": pid}, {"name": "a", "person_id": pid, "scopes": []},
               {"name": "a", "person_id": pid, "scopes": ["root"]}, {"name": "a", "person_id": pid, "expires_in_days": 366}, {"name": "a", "person_id": pid, "expires_in_days": 0},
               {"name": "a", "person_id": pid, "quotas": {"max_vms": 1}}, {"name": "a", "person_id": pid, "auto_approve": True}, {"name": "a", "person_id": pid, "token": "msk_x"}]
        for body in bad:
            reply = operator.write("POST", "/api/mcp/tokens", body)
            expect(reply.status == 400, f"{body}: {reply.status} {reply.raw[:120]!r}")
        expect(operator.write("POST", "/api/mcp/tokens", {"name": "a", "person_id": "mp-nobody"}).status == 404, "an unknown person")
        wide = operator.write("POST", "/api/mcp/tokens", {"name": "wide", "person_id": pid, "scopes": ["read", "destroy"]})
        expect(wide.status == 400 and "must be among" in wide.body["error"]["message"], f"a token cannot have more scopes than its person: {wide.raw}")
        for body in [{}, {"name": ""}, {"name": "<i>"}, {"name": "b", "scopes": []}, {"name": "b", "scopes": ["root"]}, {"name": "b", "quotas": {"max_vms": 0}}, {"name": "b", "auto_approve": True}]:
            expect(operator.write("POST", "/api/mcp/people", body).status == 400, f"person {body}")
        duplicate = operator.write("POST", "/api/mcp/people", {"name": "ayu"})
        expect(duplicate.status == 409 and duplicate.body["error"]["code"] == "name_taken", duplicate.raw)
        expect(person["scopes"] == ["read", "create"] and person["quotas"] == {"max_vms": 3, "max_vcpu": 8, "max_ram_mb": 16384, "max_disk_gb": 200, "creates_per_day": 10, "gpu_memory_gb": 8}, person)
        expect(person["tokens"] == 0 and person["vms_alive"] == 0 and person["disabled_at"] is None and person["last_used_at"] is None, person)
        changed = operator.write("PATCH", f"/api/mcp/people/{pid}", {"scopes": ["read"], "quotas": {"max_vms": 1}}).body["person"]
        expect(changed["scopes"] == ["read"] and changed["quotas"]["max_vms"] == 1 and changed["quotas"]["max_vcpu"] == 8, changed)
        for body in [{}, {"name": "New"}, {"scopes": []}, {"quotas": {"max_vms": 0}}]:
            expect(operator.write("PATCH", f"/api/mcp/people/{pid}", body).status == 400, f"patch {body}")
        expect(operator.write("PATCH", "/api/mcp/people/mp-nobody", {"scopes": ["read"]}).status == 404, "patch of an unknown person")
        expect(operator.write("POST", "/api/mcp/people/mp-nobody/disable").status == 404, "disable of an unknown person")
        listed = operator.request("GET", "/api/mcp/people").body["people"]
        expect([row["name"] for row in listed] == ["Ayu"], listed)
        token_text, token = make_token(operator, pid, "t", scopes=["read"])
        days = _iso(token["expires_at"]) - _iso(token["created_at"])
        expect(abs(days - 90 * 86400) < 5, f"the default life is 90 days, not {days}")


def _iso(text):
    import datetime
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def check_mcp_every_tool_call_is_audited_with_the_token_name_and_the_activity_route_shows_it():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "audited", scopes=["read"])
        client.tool("list_machines")
        client.tool("create_vm", {"size": "small"})
        entries = operator.request("GET", "/api/mcp/activity?limit=20").body["activity"]
        expect([(row["actor"], row["action"], row["status"]) for row in entries] == [("mcp:audited", "mcp.create_vm", "refused"), ("mcp:audited", "mcp.list_machines", "ok")], entries)
        expect(all(set(row) >= {"at", "actor", "action", "target", "status"} for row in entries), entries)
        expect(all(row["person"] == "audited" and len(row["token_prefix"]) == 8 for row in entries), f"the activity names the person and the token by its prefix: {entries}")
        expect(operator.request("GET", "/api/mcp/activity?limit=1").body["activity"][0]["action"] == "mcp.create_vm", "limit")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
