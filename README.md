# MetaService

Cross-architecture virtualization manager bridging native macOS environments and Linux fleets (x86_64 and Arm).

One central **Root** registers machines on a network and manages them. Each registered machine runs a small
**Agent** that creates, starts, stops and deletes the VMs on that machine.

Root → Machines → Agents → VMs.

Status: early planning. Nothing is built yet.
