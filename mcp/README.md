# AI access (MCP)

An AI client (Claude Code, Cursor, any MCP client) can create and manage VMs through MetaService. It connects to `https://meta.ruvio.site/mcp` with a token that belongs to a **person** (a name like "Ayu", not a login). The parent checks what the token may do, applies the person's limits, runs the call at once, writes it to the log, and records who made every VM. The full agreement between the parts is in `SPEC.md` (section 10 is the current design).

## Connect Claude Code

1. In the panel open **Settings**, find **AI access (MCP)**. Under **People**, press **Add person**: a name, what they may do, and their limits. (Do this once per person.)
2. Under **Tokens** press **Create token**: choose the person, name the token (for example `laptop`), tick what it may do (never more than the person may) and the days it lasts.
3. Copy the token when it is shown. **It is shown once and cannot be shown again.**
4. In a terminal, run the line from the **Connect** box, with your token in place of the placeholder:

```
claude mcp add --transport http metaservice https://meta.ruvio.site/mcp --header "Authorization: Bearer <YOUR_TOKEN>"
```

## Connect another client

A client that reads a JSON file of MCP servers takes this (the panel shows it with your endpoint):

```json
{
  "mcpServers": {
    "metaservice": {
      "type": "http",
      "url": "https://meta.ruvio.site/mcp",
      "headers": { "Authorization": "Bearer <YOUR_TOKEN>" }
    }
  }
}
```

## What the AI can call

| Tool | Needs | What it does |
|---|---|---|
| `list_machines` | read | Lists the machines and how much room they have. Shared machines only with the `shared` scope. |
| `machine_capacity` | read | Says what a new VM can still get on one machine. |
| `list_vms` | read | Lists the VMs this person made. Other VMs are only counted. |
| `vm_status` | read | Shows one VM: state, size, address, how to log in with SSH. |
| `create_vm` | create | Creates a VM (small, medium, large or custom) and waits for it to run. A repeated `idempotency_key` never makes a second VM. |
| `start_vm`, `stop_vm` | create | Start or stop a VM this person made. |
| `delete_vm` | destroy | Deletes a VM this person made. |
| `get_request` | read | Checks a create, start, stop or delete that is still running. |

## Guardrails

- **People and scopes.** A person can only do what they were given: `read`, `create`, `destroy`, `gpu` (a GPU memory limit on a new VM), `shared` (machines that joined through Share a PC). A token gets the same or fewer. A new person gets `read` and `create`.
- **Limits belong to the person.** VMs alive at once (3), vCPU (8), RAM (16 GB) and disk (200 GB) in total, creates per day (10), GPU memory (8 GB, only with `gpu`). They count over all the person's tokens, so a second token never doubles them. Over a limit the AI is told the limit and what is left. Also 60 requests a minute per token.
- **Ownership.** Start, stop and delete only work on VMs the same person made, with any of their tokens. Other people's VMs are invisible to them.
- **No approvals.** People are trusted, so calls run at once once scope, limits and ownership pass. Edit a person to change what they may do, or **Disable** them to stop all their tokens at once. Their VMs stay and keep their creator record.
- **Expiry.** A token lasts 90 days by default, one year at most.
- **No shell, no secrets.** No tool runs a command on a machine, and none returns a token, key or password.
- **Revoke.** Press **Revoke** in the token table. It stops at once. The VMs it made keep running.
- **Who made which VM.** Every VM the parent creates, from the panel or from an AI client, gets a record that is never edited: who (the panel operator, or the person, the token prefix and the AI client's name), from which address, and when. It shows as **Created by** with a short fingerprint ("Ayu (MCP) · 7f3a9c21") on the Compute views, the All VMs table and the VM page, which also shows the details. If a stored record no longer matches its seal, the VM page says **record altered** in red. A VM the parent did not make shows "unknown origin"; the first VMs, made before this feature, show "admin (recorded afterwards)".

## What is logged

Every call writes one row: when, the person, the tool, the machine or VM, and the result. The last 20 show under **Recent activity**. The log never holds the token or any value that could be a key. The token itself is stored only as a hash, with its first characters kept to tell tokens apart.

## If something goes wrong

- **The panel says "AI access is not available on this parent."** The parent is too old. Update it.
- **The client gets 401.** The token is wrong, expired or revoked, or its person is disabled. Make a new token or Enable the person.
- **A create or delete is slow.** The AI can check it with `get_request`.
- **"max_vms is 3 and 3 are alive".** The person hit a limit. Delete one of their VMs, or Edit the person to raise the limits.
- **A call is refused with 403.** The address the client uses is not the panel's own host, or the scope is missing.
- **You lost a token.** It cannot be shown again. Revoke it and make a new one.
