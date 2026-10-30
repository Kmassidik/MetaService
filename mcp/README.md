# AI access (MCP)

An AI client (Claude Code, Cursor, any MCP client) can create and manage VMs through MetaService. It connects to `https://meta.ruvio.site/mcp` with its own token. The parent checks what the token may do, applies its limits, asks a person before anything risky, and writes every call to the log. The full agreement between the parts is in `SPEC.md`.

## Connect Claude Code

1. In the panel open **Settings**, find **AI access (MCP)** and press **Create token**. Give it a name, tick what it may do, set the limits and the days it lasts.
2. Copy the token when it is shown. **It is shown once and cannot be shown again.**
3. In a terminal, run the line from the **Connect** box, with your token in place of the placeholder:

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
| `list_vms` | read | Lists the VMs this token made. Other VMs are only counted. |
| `vm_status` | read | Shows one VM: state, size, address, how to log in with SSH. |
| `create_vm` | create | Creates a VM (small, medium, large or custom) and waits for it to run. A repeated `idempotency_key` never makes a second VM. |
| `start_vm`, `stop_vm` | create | Start or stop a VM this token made. |
| `delete_vm` | destroy | Deletes a VM this token made. Always waits for your approval. |
| `get_request` | read | Checks a request that waited for approval or is still running. |

## Guardrails

- **Scopes.** A token can only do what it was given: `read`, `create`, `destroy`, `gpu` (a GPU memory limit on a new VM), `shared` (machines that joined through Share a PC). A new token gets `read` and `create`.
- **Limits.** Per token: VMs alive at once (3), vCPU (8), RAM (16 GB) and disk (200 GB) in total, creates per day (10), GPU memory (8 GB, only with `gpu`). Over a limit the AI is told the limit and what is left. Also 60 requests a minute per token.
- **Ownership.** Start, stop and delete only work on VMs the same token made. Other VMs are invisible to it.
- **Approvals.** These wait for a person under **Waiting for approval**: every delete, a create with a GPU limit, a large or custom VM above the medium size, and a create on a shared machine. You see the token name and the exact request, and press Approve or Deny. Requests nobody decides expire after 24 hours. A token cannot approve anything. A token made with auto-approve skips this: leave it off unless you fully trust the client.
- **Expiry.** A token lasts 90 days by default, one year at most.
- **No shell, no secrets.** No tool runs a command on a machine, and none returns a token, key or password.
- **Revoke.** Press **Revoke** in the token table. It stops at once. The VMs it made keep running and stay listed as its own.

## What is logged

Every call writes one row: when, the token's name, the tool, the machine or VM, and the result. The last 20 show under **Recent activity**. The log never holds the token or any value that could be a key. The token itself is stored only as a hash, with its first characters kept to tell tokens apart.

## If something goes wrong

- **The panel says "AI access is not available on this parent."** The parent is too old. Update it.
- **The client gets 401.** The token is wrong, expired or revoked. Make a new one.
- **A request says it needs approval.** Open Settings, AI access, and Approve or Deny it. The AI can check it with `get_request`.
- **"max_vms is 3 and 3 are alive".** The token hit a limit. Delete a VM it made, or make a token with higher limits.
- **A call is refused with 403.** The address the client uses is not the panel's own host, or the scope is missing from the token.
- **You lost a token.** It cannot be shown again. Revoke it and make a new one.
