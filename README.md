# MetaService

Cross-architecture virtualization manager bridging native macOS environments and Linux fleets (x86_64 and Arm).

One central **Root** registers machines on a network and manages them. Each registered machine runs a small
**Agent** that creates, starts, stops and deletes the VMs on that machine.

Root → Machines → Agents → VMs.

A machine can be added only if it is reachable over SSH (key login) from the Root's network.

Status: in development. The Root, the macOS and Linux Agents, the chat bundle and the AI proxy are built and tested locally.
