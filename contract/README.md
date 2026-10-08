# Contract

`openapi.yaml` is the API between the Root and every Agent. An Agent that passes the conformance tests works with
the Root, whatever language it is written in.

- `spec.py` loads the contract and validates JSON against it (used by the Fake Agent and the tests).
- `tests/` is the conformance suite. It runs against any Agent by address.
- `tests/run_fake.py` runs the whole suite against the Fake Agent in `agent/fake/`.
- `tests/mutation.py` checks the suite itself: deliberately broken Fake Agents must fail it.

Run inside the Nix dev shell (`nix develop`): `python3 -m contract.tests.run_fake` and `python3 -m contract.tests.mutation`.
