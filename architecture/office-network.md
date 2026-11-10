# Office network and cabling

This document explains the physical and logical network shape without publishing exact addresses, device MACs, or credentials. Those belong in the private operations knowledge base.

## Physical path

```text
Machine network interface
        │ Ethernet cable
        ▼
WeWork desk wall jack
        │ Patch-panel / cross-connect
        ▼
WeWork switch port
        │ VLAN assignment
        ▼
Member/floor network or public gateway
```

A machine cannot reach the public gateway merely because a static IP is configured. The complete physical and VLAN path must work.

## Current wall-jack model

| Wall label | Switch port | Role | Current intent |
|---|---|---|---|
| `26192-O` | `ge-5/0/6` | Primary public connection | Working; do not change during secondary work |
| `26191-O` | `ge-5/0/1` | Secondary public connection | Enable for another machine |

These are **physical jack labels**, not TCP/SSH ports.

## VLANs

- **Member/floor VLAN:** supplies a private address through DHCP and provides ordinary office connectivity.
- **VLAN999:** public/static connection. It supplies no DHCP lease; the machine must use the assigned static IP, mask, and gateway.

A member DHCP address means the interface is still on the member/floor network. It does not prove that VLAN999 is available.

## Current secondary-machine layout

The newest test machine uses two interfaces:

| Interface | Role | Configuration |
|---|---|---|
| Built-in Ethernet | Secondary public connection | Persistent Manual public configuration |
| WiFi | Management lifeline and default route | Ordinary member connectivity |

This split lets us configure Ethernet without losing the management connection. Tailscale over the management link was used for setup.

## Gateway and ARP test

A successful public connection requires both:

1. The configured gateway responds.
2. ARP resolves the gateway to a real MAC address.

```text
100% gateway loss + no ARP entry = no working Layer-2 public path
```

That result means the public VLAN is not reaching the machine, the wall/switch mapping is wrong, or port-side registration is still required. It does not prove which one; WeWork must verify its side.

## Why WeWork may request a device MAC

A switch learns which port a device uses from its source Ethernet MAC. WeWork may use it to:

- Locate the actual switch port
- Verify the current VLAN
- Apply port security or MAC registration
- Confirm that the new device is permitted on the public connection

MAC registration is administrative port control, not strong cryptographic identity. MAC addresses can be spoofed.

## No local router required for direct public IP

A machine can hold a public IP directly on its Ethernet interface:

```text
Machine → wall jack → WeWork switch → public gateway → internet
```

A local router/MikroTik becomes useful only if we intentionally want private addresses behind NAT, local firewall/NAT policy, or several machines sharing router-owned public addresses.

## Safe operating rules

- Keep a separate management connection while testing public Ethernet.
- Do not modify the working primary wall jack while enabling the secondary.
- Back up network settings before mutation.
- Test only the intended interface.
- Roll back to DHCP if the gateway test fails and the runbook requires it.
- Do not report public access until gateway, ARP, and external SSH all pass.
- Keep exact addresses, device MACs, credentials, and evidence files in the private operations records.
