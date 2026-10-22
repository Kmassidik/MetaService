# Contract

`openapi.yaml` is the API between the Root and every Agent. An Agent that passes the conformance tests works with
the Root, whatever language it is written in.

- `spec.py` loads the contract and validates JSON against it (used by the Fake Agent and the tests).
- `tests/` is the conformance suite. It runs against any Agent by address.
- `tests/run_fake.py` runs the whole suite against the Fake Agent in `agent/fake/`.
- `tests/mutation.py` checks the suite itself: deliberately broken Fake Agents must fail it.

Run inside the Nix dev shell (`nix develop`): `python3 -m contract.tests.run_fake` and `python3 -m contract.tests.mutation`.

## Versions

- Added without a version change (optional, macOS helper only; a helper without it answers 404): the console: helper WebSocket `GET /v1/workloads/{id}/terminal`, panel routes `POST /api/machines/{id}/workloads/{workload}/terminal` and `GET /api/terminal/{ticket}`. See `docs/console-contract.md`.
- Added without a version change (optional; a helper without it answers 404): the monitor: helper `GET /v1/stats` and panel route `GET /api/machines/{id}/stats`. See `docs/monitor-contract.md`. Later, also without a version change: the optional query `processes` (`1` or `0`, absent means `1`) on both routes; `0` skips the scan of programs (`processes: []`), other values are a 400.
- Added without a version change (optional; a helper without it simply leaves it out): on a workload, `stopped_reason` (`exit_code` or null, `log_tail`: why a VM that stopped by itself stopped) and `init_mode` (`systemd` or `plain`). A create that fails because the VM never came up carries the plain-words reason (and the last lines the VM printed) in the failed command's `result.error`. The Root returns both fields on every workload of `GET /api/machines` (null when empty).
- Added without a version change (optional; a helper without it answers 404, and the parent then treats the machine as having only `blank`): ready-made images. Helper `GET /v1/images` (what the machine has prepared: `{ "images": [ { "id", "ready", "built_at" } ] }`), panel routes `GET /api/images` (the parent's catalog: id, title, description, state `ready` or `planned`, reason) and `GET /api/machines/{id}/images` (catalog joined with the machine: `ready`, `available`, `reason`, and `helper` = `answered`, `old_helper` or `unreachable`), and the optional `bundle` (a catalog id) on `POST /api/workloads` and on the helper's `POST /v1/workloads`. On the panel route an unknown id is a 400 `invalid_input`, a listed but `planned` id is a 409 `image_not_available` with the catalog's reason, and `blank` or nothing is today's request. The parent sends `bundle` to a helper only for a ready image other than `blank`. A free `image` name from the browser is refused with a 400; the helper's `image` field comes only from the machine's own saved default.
- 1.3.0 (additive): `Facts` carries `agent_version` (the same text as `/v1/health`) and `engine` (`name`, `version` or null, `ready`); `POST /v1/bundle/uninstall` turns the chat off on the machine or in a workload and keeps its conversations; command type `bundle_uninstall`. The Root accepts a helper that does not say these (they stay null in the panel); an Agent that claims 1.3.0 must.
