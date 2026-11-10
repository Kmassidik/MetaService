# Copy-ready prompt — hybrid MetaService + AWS + Liquid Compute

Use this prompt to produce an implementation-ready PRD. It does not authorize deployment.

```text
You are designing an integration, not implementing it yet.

Context:
MetaService is my self-hosted compute control plane. One parent manages on-prem machines through native helpers. macOS helpers use Apple Container; Linux helpers use Incus. The parent already handles machine inventory, resource budgets, managed VM lifecycle, external Docker/Incus/Apple discovery, sandbox API keys, expiration, pause/resume/kill, command IDs, usage records, and audit. Existing services must remain untouched.

I want a hybrid on-prem + cloud design:
1. MetaService remains the on-prem ownership and Compute layer.
2. AWS is considered for cloud burst, container jobs, object storage, queues, IAM, and observability.
3. ECS Anywhere is the first candidate for compatible on-prem Linux container tasks, with EC2/Fargate in the same cloud model where appropriate.
4. Liquid Compute is NOT a runtime. Its public product describes a compute market/exchange: reference pricing, verification, clearing, settlement, financing, and physical delivery. Treat it as a potential market/evidence/delivery integration only.
5. No Liquid Compute API documentation is currently available in this conversation. Do not invent endpoints, authentication, contract fields, or pricing/settlement behavior.

Read these architecture files first:
- architecture/README.md
- architecture/office-network.md
- architecture/hybrid-aws-liquid-compute.md
- docs/ARCHITECTURE.md (historical; follow newer handover/current-state documents where they disagree)
- docs/PRD-shared-compute.md (draft/history, not shipped functionality)
- the latest private MetaService handover available in the workspace

Write a PRD with:

A. Goals and non-goals
- One reversible, non-sensitive proof-of-concept workload.
- No production GPU interruption.
- No migration of existing services.
- No marketplace automation or payout automation.
- No shared ownership of one workload between AWS and MetaService.

B. Architecture and ownership
- Exact responsibility of MetaService, ECS/ECS Anywhere, EC2, S3, SQS, IAM, CloudWatch, and Liquid Compute.
- Which controller owns each workload state transition.
- How AWS-created containers are identified so MetaService does not accidentally stop/restart them as generic external Docker services.
- How cloud and on-prem usage records remain separate and reconcilable.

C. Liquid Compute discovery requirements
- A checklist of official documentation and access needed before implementation.
- Supported hardware verification, especially consumer GPUs, DGX ARM64, and Apple Silicon.
- Verification/evidence format, physical-delivery protocol, contract identifiers, authentication, pricing units, settlement, disputes, and failure/refund rules.
- If any answer is unavailable, mark it BLOCKED rather than guessing.

D. AWS implementation plan
- Compare ECS Anywhere versus a direct EC2 provider adapter for this use case.
- Verify OS/CPU/GPU compatibility for the proposed test machine.
- Define IAM boundaries, S3 prefixes, quotas, cost ceilings, logs, and disconnect behavior.
- Include the current external-instance price only if verified from the official AWS page at planning time.
- No production registration until a separate runbook is approved.

E. Data model and APIs
- Propose provider-neutral workload and usage identities.
- Propose a read-only verification/delivery bundle for Liquid Compute.
- Define idempotency, retries, command finality, audit, and error behavior.
- Keep credentials out of Git and documents.

F. Security and network
- Default-deny access from proof-of-concept workloads to the office LAN.
- No host Docker socket, host home mount, or host credentials in the workload.
- Use outbound TLS and S3 first; justify any VPN/Direct Connect requirement rather than assuming it.
- Define resource, time, network, and data-retention limits.

G. Phases and acceptance tests
- Documentation/API discovery
- Read-only AWS discovery and cost estimate
- One reversible container job
- Read-only Liquid Compute evidence export
- For each phase, give observable pass/fail checks and a rollback.

H. Open decisions
List only decisions that materially change the architecture. Provide a recommended default for each.

Do not write code, create AWS resources, register machines, contact Liquid Compute, or deploy anything. Return the PRD and the missing-information list first.
```
