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
- 1.3.0 (additive): `Facts` carries `agent_version` (the same text as `/v1/health`) and `engine` (`name`, `version` or null, `ready`); `POST /v1/bundle/uninstall` turns the chat off on the machine or in a workload and keeps its conversations; command type `bundle_uninstall`. The Root accepts a helper that does not say these (they stay null in the panel); an Agent that claims 1.3.0 must.
