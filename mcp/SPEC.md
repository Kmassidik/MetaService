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

These need a person: `delete_vm`; `create_vm` with a GPU limit, with `size` `large` or `custom` above the medium preset, or on a shared machine; unless the token has `auto_approve`. The call does not run: it stores the action and answers `{"status":"needs_approval","request_id":"...","message":"A person must approve this in the panel (Settings, AI access)."}`. In the panel an operator sees the token's name, the exact action and size, and presses Approve or Deny. On Approve the parent runs the stored action (as actor `mcp:<token name>`, approved by the operator) and keeps the result for `get_request`. Pending approvals expire after 24 hours. A token cannot approve anything, and no tool approves.

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
