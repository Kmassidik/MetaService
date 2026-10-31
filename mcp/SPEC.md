# MCP: AI clients create and manage VMs through MetaService

An MCP server inside the parent (`https://meta.ruvio.site/mcp`), with its own API tokens. An AI client (Claude Code, Cursor, any MCP client) calls a few outcome-shaped tools; the parent applies scopes, quotas and approvals, then uses the same services the panel uses. This file is the single agreement between the parts: the parent (Swift), the panel section (Svelte) and the docs.

## 1. Rules

- It runs **inside the parent** (`control-plane/arm64`, Swift, Hummingbird), as thin adapters over the existing services (`services.workloads`, machines, GPU booking, audit). No second server.
- **The AI is treated as untrusted and sometimes wrong.** Every tool call is checked against the token's scopes and quotas; risky calls need a person to approve in the panel; everything is audited with the token's name.
- **No raw shell, no secrets out.** No tool runs a command on a machine or returns a token, key or password.
- Match the code around it (`AGENTS.md`: no nested `if`, about 400 lines per file, a test for every feature, no hardcoded secrets). Swift builds and tests only on the Mac Mini.

## 2. Protocol (Streamable HTTP, JSON replies only)

`POST /mcp` with one JSON-RPC 2.0 message per request (batches are refused with a JSON-RPC error). `Content-Type: application/json`; the client sends `Accept: application/json, text/event-stream` and gets `application/json`. `GET /mcp` and `DELETE /mcp` answer 405 (no server-initiated stream, no session). Methods: `initialize` (protocol version negotiation: answer the client's version when it is one of `2025-06-18`, `2025-03-26`, `2024-11-05`, else `2025-06-18`; capabilities `{"tools":{}}`; `serverInfo` name `metaservice`), `notifications/initialized` (202, empty body), `ping`, `tools/list`, `tools/call`. Anything else: JSON-RPC error -32601. Malformed: -32700 / -32600 / -32602 as the spec says.

Tool results: `content: [{"type":"text","text":"<the JSON, pretty>"}]`, plus `structuredContent` (the same object) when the negotiated version is `2025-06-18` or later. A tool that is refused or fails gives `isError: true` with a plain sentence that tells the AI what to do next (never a stack trace). HTTP errors only for transport problems.

**Origin and host:** a request with an `Origin` header whose host is not the panel's own host is refused (403); a request without `Origin` (a normal MCP client) is fine. The parent's existing Host check applies.

## 3. Tokens

- Format `msk_` + 43 URL-safe base64 characters (256 bits). Shown **once**, when made in the panel. Stored only as a SHA-256 hash; the first 8 characters after `msk_` are kept as a `prefix` to tell tokens apart. Lookup is by hash.
- `Authorization: Bearer <token>`. Missing, unknown, revoked or expired: HTTP 401 with `WWW-Authenticate: Bearer realm="metaservice"`. `last_used_at` is updated at most once a minute.
- Fields: name, prefix, scopes, quotas, `auto_approve` (default false), `expires_at` (default 90 days, never longer than a year), created by, created at, revoked at.
- **Scopes:** `read` (list and status tools), `create` (create, start, stop of VMs this token made), `destroy` (delete VMs this token made), `gpu` (a GPU memory limit in create_vm), `shared` (machines that joined through Share a PC). A new token's default: `read` + `create`.
- **Quotas** (defaults in code, per token, editable when it is made): `max_vms` 3 alive at once, `max_vcpu` 8 and `max_ram_mb` 16384 and `max_disk_gb` 200 summed over its alive VMs, `creates_per_day` 10. `gpu_memory_gb` cap 8 when `gpu` is on.
- Rate limit: 60 requests a minute per token (create 10 a minute); body limit 64 KiB.
- **Ownership:** every VM a token creates is recorded for it (`token_workloads`). `stop_vm`, `delete_vm` and `start_vm` only work on VMs the same token created. Any other VM is invisible in `list_vms` (listed as `others` count only) and refused by id.

## 4. Tools (names, inputs, outputs)

All inputs are JSON objects with `additionalProperties: false`. Each tool has a one-sentence `description` that tells the AI when to use it and what it costs.

| Tool | Scope | Input | Result |
|---|---|---|---|
| `list_machines` | read | none | `{"machines":[{"id","name","state","os","arch","shared":bool,"cpu_cores","ram_total_mb","free_ram_mb","free_disk_gb","gpu":{"name","total_gb","free_gb"}|null,"engine_ready":bool}]}`; shared machines only with the `shared` scope |
| `machine_capacity` | read | `machine` | what a new VM can still get on it: `free_vcpu`, `free_ram_mb`, `free_disk_gb`, `gpu_free_gb`, the size presets that fit |
| `list_vms` | read | `machine?` | `{"vms":[{"machine","id","name","state","vcpu","ram_mb","disk_gb","gpu_memory_gb","address","created_by_me":true}],"others":n}` (only this token's VMs are listed) |
| `vm_status` | read | `machine`, `vm` | one VM: state, size, address, the SSH command if it has an address, why it stopped if it did |
| `create_vm` | create | `machine?` (omit: the least loaded machine that fits), `name?`, `size` (`small`, `medium`, `large`, `custom`; the same presets as the panel's Create VM), `vcpu?`, `ram_mb?`, `disk_gb?` (custom only), `image` (an id from the panel's image list; default the panel's default), `gpu_memory_gb?` (needs `gpu`), `ssh_public_key?`, `idempotency_key?`, `wait_seconds?` (0 to 60, default 30) | creates the VM through `services.workloads.create`, waits up to `wait_seconds` for RUNNING, returns the VM (and its SSH command) or `{"status":"creating","request_id":...}` to poll. A repeated `idempotency_key` returns the same VM, never a second one. |
| `start_vm`, `stop_vm` | create | `machine`, `vm`, `wait_seconds?` | the VM after the action (or `request_id`) |
| `delete_vm` | destroy | `machine`, `vm` | always needs approval (section 5) unless the token has `auto_approve` |
| `get_request` | read | `request_id` | the state of a command or an approval this token made: `pending_approval`, `approved`, `denied`, `running`, `done` (with the VM), `failed` (with the plain reason) |

Quota or scope problems answer `isError` with the exact limit and what is left ("max_vms is 3 and 3 are alive: delete one first"). Sizes and images use the parent's own validation; its refusal text is passed on.

## 5. Approvals

**Removed in revision 2 (section 10.2).** Nothing waits for a person: a call that passes the scope, quota and ownership checks runs at once.

## 6. Data (migration after the current latest in `RootStore/Database/Migrations.swift`)

- `api_tokens` (id, name, prefix, token_hash UNIQUE, scopes_json, quotas_json, auto_approve, created_by, created_at, expires_at, last_used_at, revoked_at)
- `token_workloads` (token_id, machine_id, workload_id, created_at, deleted_at) with the idempotency key and request id of the create
- `mcp_requests` (id, token_id, kind `create|delete|start|stop`, params_json, state, command_id, result_json, created_at, decided_by, decided_at, expires_at)

## 7. Operator API (panel, session + CSRF like every operator route)

`GET /api/mcp/info` (the endpoint URL, the protocol versions, the tool names, the defaults), `GET /api/mcp/tokens`, `POST /api/mcp/tokens` (body: name, scopes, quotas, expires_in_days, auto_approve; the reply is the **only** time the token text is returned), `DELETE /api/mcp/tokens/{id}` (revoke; its running VMs stay and show as theirs), `GET /api/mcp/approvals` (pending and recent), `POST /api/mcp/approvals/{id}/approve`, `POST /api/mcp/approvals/{id}/deny`, `GET /api/mcp/activity?limit=` (audit rows whose actor starts with `mcp:`).
**Audit:** every tool call writes one row: actor `mcp:<token name>`, action `mcp.<tool>`, target machine/VM, status; never params that could hold a key, never the token.

### 7.1 Operator API: exact JSON (fixed by the parent build; all field names snake_case, times ISO 8601 UTC)

`token` (a token as the panel sees it; never the text, never the hash):
`{"id","name","prefix","scopes":["read","create"],"quotas":{"max_vms","max_vcpu","max_ram_mb","max_disk_gb","creates_per_day","gpu_memory_gb"},"auto_approve":false,"created_by","created_at","expires_at","last_used_at":null|time,"revoked_at":null|time,"status":"active"|"revoked"|"expired","vms_alive":0}`

- `GET /api/mcp/info` -> `{"endpoint":"https://meta.ruvio.site/mcp","protocol_versions":[...],"scopes":["read","create","destroy","gpu","shared"],"tools":["list_machines",...],"defaults":{"scopes":["read","create"],"quotas":{...},"expires_in_days":90,"max_expires_in_days":365,"auto_approve":false}}`
- `GET /api/mcp/tokens` -> `{"tokens":[token]}` (newest first, revoked ones included).
- `POST /api/mcp/tokens` body `{"name","scopes"?,"quotas"?,"expires_in_days"?,"auto_approve"?}` (name 1 to 40 of letters, digits, space, `.`, `_`, `-`; a live token name is unique) -> **201** `{"token":"msk_...","info":token}`. `token` is the text, shown once.
- `DELETE /api/mcp/tokens/{id}` -> 200 `{"info":token}` (revoking twice is the same answer); 404 for an unknown id.
- `GET /api/mcp/approvals` -> `{"pending":[approval],"recent":[approval]}`; `approval` is `{"id","token_id","token_name","kind":"create"|"delete"|"start"|"stop","params":{"machine","machine_name","vm","vm_name","name","size","vcpu","ram_mb","disk_gb","image","gpu_memory_gb"} (only the parts that apply; never a public key),"description":"plain sentence of the exact action and size","reason":"why a person must approve","state":"pending_approval"|"approved"|"denied"|"running"|"done"|"failed"|"expired","created_at","expires_at","decided_by":null|text,"decided_at":null|time,"message":null|text}` (`message` is the plain failure reason when `failed`).
- `POST /api/mcp/approvals/{id}/approve` and `/deny` (no body) -> 200 `{"approval":approval}` (after approve the state is `running`, `done` or `failed`); 404 unknown id; 409 `not_pending` when it was already decided or has expired; 409 `token_not_usable` when the token was revoked or has expired since.
- `GET /api/mcp/activity?limit=` (default 20, at most 200) -> `{"activity":[{"at","actor":"mcp:<token name>","action":"mcp.<tool>","target","status"}]}`, newest first, only actors starting with `mcp:`. `status` is `ok`, `refused`, `failed`, `needs_approval`, `approved`, `denied` or `replayed`.

## 8. Panel (Svelte)

A section **AI access (MCP)** on the Settings page (no new sidebar row): *Connect* (the endpoint, the ready-to-copy `claude mcp add --transport http metaservice <url> --header "Authorization: Bearer <token>"` line and a JSON snippet for other clients, with a placeholder instead of a real token), *Tokens* (table with name, prefix, scopes, quotas, last used, expiry, Revoke; a Create token dialog that shows the new token once with a Copy button and a warning), *Waiting for approval* (each request with its plain description and Approve / Deny), *Recent activity* (the last 20 calls). Same look and components as the panel; loading, empty and error states with text; hostile text only as text.

## 9. Docs

`mcp/README.md` (committed): how to connect Claude Code and another client, the tool reference, the guardrails, how to revoke, what is logged. Update `AGENTS.md`-style handover notes at the end.

## 10. Revision 2 (2026-10-31, decided by Kurnia): people, no approvals, and a creator fingerprint on every VM

Why: the panel has one login (the shared admin), but 2 or 3 known people use MCP. They are trusted, so nobody needs to approve their calls. What is missing is **who created which VM**, kept for good. Where this section and sections 3, 5, 6, 7 or 8 disagree, **this section wins**.

### 10.1 People (replaces "the token is the identity")
- New table `mcp_people` (id, name UNIQUE, scopes_json, quotas_json, created_at, disabled_at). A **person** is a name like "Ayu", not a login: there is no password and no panel account for people. The panel's one login stays the shared admin.
- Every token belongs to exactly one person (`api_tokens.person_id`, NOT NULL). Scopes: the token's scopes are a subset of its person's scopes. **Quotas are the person's**, counted over all the person's tokens (a second token never doubles the quota). Ownership is by person: a person's second token sees and changes the same VMs as the first; another person's VMs are invisible and refused by id.
- Migration 30 (after 29): create `mcp_people`, add `api_tokens.person_id`, and for each token that already exists create a person from the token's name (move its scopes and quotas to that person). Production has no tokens yet, but the migration must still be right.
- Disabling a person (`disabled_at`) makes all their tokens answer 401 at once; their VMs stay and keep their creator record.
- Operator API (panel session + CSRF): `GET /api/mcp/people` -> `{"people":[{"id","name","scopes","quotas","tokens":n,"vms_alive":n,"last_used_at","disabled_at"}]}`; `POST /api/mcp/people` {name, scopes, quotas}; `PATCH /api/mcp/people/{id}` (scopes, quotas); `POST /api/mcp/people/{id}/disable` and `/enable`. `POST /api/mcp/tokens` takes `person_id` (required) instead of quotas; the token list items carry `person_id` and `person_name`.

### 10.2 No approvals
Remove the approval flow completely (no dead code): the `needs_approval` answers, the `/api/mcp/approvals*` routes, the panel's "Waiting for approval" block, `api_tokens.auto_approve`, the approval states. Tools now run at once after the scope, quota and ownership checks (a GPU limit still needs the `gpu` scope, delete still needs `destroy`, shared machines still need `shared`; a person can only delete VMs they created). `mcp_requests` stays only to track a slow create/start/stop/delete for `get_request` and idempotency, with the states `running`, `done`, `failed`. Delete the approval tests and checks and the approval wording in `mcp/README.md` and the panel; update section 5 of this file to say "removed".

### 10.3 The creator fingerprint on every VM
- New append-only table `vm_origin` (machine_id, workload_id, kind `panel` or `mcp`, actor, person_id, person_name, token_id, token_prefix, client_name, client_version, source_ip, request_id, created_at, deleted_at, deleted_by, seal). It is written by the **workload service whenever the parent creates a VM**, for **both** doors: the panel (kind `panel`, actor = the panel operator's name, no person) and MCP (kind `mcp`, person, token prefix, the MCP client's `clientInfo` name and version from `initialize`, the caller's IP). A VM the parent did not create (or made before this feature) shows as "unknown origin". Rows are never edited; the only later change is `deleted_at` and `deleted_by` when the parent deletes the VM, by the same service (a delete through MCP records the person, through the panel the operator).
- **seal** = the first 16 hex characters of HMAC-SHA256 over the canonical record (the fields in a fixed order, without the seal), keyed with a key the parent derives from its secret store (use the existing `services.secrets` machinery; never the token). The **fingerprint** shown to people is the first 8 characters of the seal. A read recomputes the seal; a mismatch is reported as `altered`, never silently shown.
- Read API (panel session): `GET /api/machines/{id}/workloads/{workload}/origin` -> `{"origin":{kind, actor, person_name, token_prefix, client, source_ip, created_at, deleted_at, deleted_by, fingerprint, intact: bool}|null}`; and the workloads in the machine answers get a short `created_by` object `{kind, label, fingerprint}` (label "Ayu (MCP)" or "panel (<operator>)") so lists need no second call. MCP `vm_status` and `list_vms` include the same short `created_by` for the token's own VMs.
- Every audit row for a VM action (create, start, stop, delete) already has an actor; for MCP the actor becomes `mcp:<person name>` and the detail carries the token prefix and the client name (never the token, never keys).
- Not in this revision: stamping the creator onto the VM inside the machine (it would need the helpers); write it down as a possible later step.

### 10.4 Panel changes
- *AI access (MCP)* gets a **People** table (name, scopes, quota line, tokens, VMs alive, last used, Disable/Enable; an Add person dialog and an Edit dialog for scopes and quotas). Creating a token asks **which person** (no quota fields there). The Waiting-for-approval block and every approval word are removed. Recent activity shows the person.
- VM lists and VM pages show **Created by**: the label and the short fingerprint (for example "Ayu (MCP) · 7f3a9c21"), "panel (kurnia) · 5b02d1ee", or "unknown origin"; the VM page also shows client, token prefix, source IP and time, and "record altered" in red when `intact` is false. Where this goes on the existing Compute views (Building room list / Table / Cards) and the VM page follows the earlier lesson: all three Compute views and the VM page, aligned, each checked by screenshot. The Machines list and the sidebar get no change.

### 10.5 What the parent build decided beyond 10.1 to 10.4 (the contract for the panel)
- **Backfill (decided by Kurnia).** Every VM the parent lists when this ships, and that has no record, is recorded once at Root start (not in the migration: the seal needs the parent's key) as kind `panel`, actor `admin`, `backfilled` true, `created_at` null, sealed like any other row. A settings row `vm_origin_backfilled_at` is written in the same transaction, so it never runs again: a VM that appears later without a record stays "unknown origin". `backfilled` is part of the sealed record.
- **Origin read** `GET /api/machines/{id}/workloads/{workload}/origin` -> `{"origin": null | {"kind","label","actor","person_name","token_prefix","client","source_ip","created_at","backfilled","deleted_at","deleted_by","fingerprint","intact"}}`. `client` is one text, "claude-code 2.0.1" (name, then version), or null. `created_at` is null for a backfilled record. `deleted_by` is the actor that deleted the VM: `mcp:<person>` or the panel operator's name. `label` is the same text the short form carries. An id the parent has no record for answers `{"origin": null}` with status 200.
- **Short `created_by`** on every workload of `GET /api/machines` and `GET /api/machines/{id}`: `{"kind":"mcp"|"panel"|"unknown","label","fingerprint":text|null,"intact":bool}`. Labels: "Ayu (MCP)", "panel (kurnia)", "admin (recorded afterwards)", "unknown origin". A VM without a record gets the object `{"kind":"unknown","label":"unknown origin","fingerprint":null,"intact":true}`, never null, so a list needs no special case. `intact` false means the stored record no longer matches its seal: show it in red as "record altered".
- **MCP** `list_vms` and `vm_status` carry the same short `created_by` object (and still `created_by_me: true`). MCP actors are `mcp:<person name>`; an audit row of a tool call carries `token_prefix` and `client` in its detail.
- **People API answers** (all `{"person": person}` except the list): `person` is `{"id","name","scopes","quotas","tokens","vms_alive","last_used_at","created_at","disabled_at"}`; `tokens` counts tokens that are not revoked. `POST /api/mcp/people` -> 201, 409 `name_taken` (names are unique ignoring case). `PATCH` takes `scopes` and/or `quotas` (a name never changes); nothing named is 400. `POST .../disable` and `.../enable` -> 200 with the person (repeating is harmless); an unknown id is 404.
- **Tokens**: `POST /api/mcp/tokens` takes `name`, `person_id` (required), `scopes` (optional, a subset of the person's; default the person's), `expires_in_days` (1 to 365, default 90). 404 for an unknown person, 409 `person_disabled` for a disabled one, 400 when the scopes are not a subset. Token names need not be unique. Token list items: `{"id","name","prefix","person_id","person_name","scopes","created_by","created_at","expires_at","last_used_at","revoked_at","status","client_name","client_version"}` (no quotas). A token's effective scopes are the overlap of its own and its person's, so reducing a person's scopes takes the scope from every token at once.
- **Activity** rows also carry `person`, `token_prefix` and `client`. `GET /api/mcp/approvals*` no longer exist (404).
- **Rate limits**: 60 requests a minute per token; 10 creates a minute per person.
- **Migration 30** turns each existing token into a person (named like the token, with its scopes and quotas; a name used twice becomes one person from the newest token), moves ownership, quotas and idempotency keys to the person, drops `api_tokens.quotas_json` and `auto_approve`, and ends requests that were waiting for approval as `failed` ("Approvals were removed").
- **The MCP client's name** is what it said in the last `initialize` on that token; it is kept on the token and copied onto the record of each VM created afterwards. A client that never says hello leaves it empty.

