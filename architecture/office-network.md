# Office network: why a plugged-in cable can still fail

You can plug in Ethernet, set the correct public IP, and still get no connection. That does not mean the IP is broken. It means one part of the path between the machine and the public gateway is not carrying the right network.

## Follow the path

```text
Your machine
   │ Ethernet cable
   ▼
Desk wall jack
   │ Patch-panel connection
   ▼
WeWork switch port
   │ VLAN setting
   ▼
Member/floor network or public gateway
```

Every link must be correct:

1. The cable is physically connected.
2. The wall jack is cross-connected to the expected switch port.
3. That switch port carries the intended VLAN.
4. Port security or MAC registration allows the device, if required.
5. The machine uses the correct static IP, mask, and gateway for that VLAN.

## The two wall jacks

| Label on the wall | Switch port | Role |
|---|---|---|
| **26192-O** | `ge-5/0/6` | Primary public connection, already working |
| **26191-O** | `ge-5/0/1` | Secondary public connection we want to enable |

These are **jack labels**, not TCP ports. Public SSH still uses TCP 22.

## Member network versus VLAN999

### Member/floor network

- DHCP gives the machine an address automatically.
- It provides ordinary office connectivity.
- It is the safe management path while testing.

### VLAN999

- It does **not** provide DHCP.
- You must configure the assigned public IP, subnet mask, and gateway manually.
- Receiving a member DHCP address proves the interface is on the member network, not VLAN999.

This is why “the cable works” and “the public IP works” are different statements.

## The gateway and ARP test, in human terms

When the Mac is configured correctly, it asks the local network:

> “Which device has this gateway IP?”

The gateway should answer with its MAC address. The Mac stores that answer in its ARP table and can then send packets to the gateway.

### A good result

```text
Gateway replies → ARP entry appears → public path can be tested
```

### The failure we saw

```text
100% gateway loss + no ARP entry = no working public Layer-2 path
```

This proves the public conversation never reached the gateway. It does **not** prove which side caused it.

Possible causes:

- The wall jack maps to a different switch port.
- VLAN999 is not enabled on that port.
- The new machine’s MAC has not been registered, if WeWork requires registration.
- The static configuration is on the wrong interface.

WeWork needs to check its side to distinguish these.

## Why WeWork asks for the machine’s MAC address

A switch learns which physical port a device uses from the source Ethernet MAC.

```text
Device MAC → switch learns port → WeWork verifies VLAN and registration
```

They may use it to:

- Find the real switch port
- Confirm the wall-jack mapping
- Check the VLAN
- Allow the device through port security

MAC registration is useful for administration, but it is not strong identity proof because a MAC can be spoofed.

## Why the new machine uses Ethernet and WiFi

The newest test machine uses:

| Interface | Purpose |
|---|---|
| **Built-in Ethernet** | Secondary public IP on VLAN999 |
| **WiFi** | Management/default route and Tailscale lifeline |

This lets us change Ethernet without losing the management session. When WeWork enables the public path, we can test public SSH without visiting the office.

## Do we need a MikroTik or another router?

Not for a machine that directly owns a public IP:

```text
Machine → wall jack → WeWork switch → public gateway → internet
```

A local router becomes useful only when we deliberately want:

- Private addresses behind NAT
- One router-owned public IP shared by several machines
- Local firewall/NAT rules
- More controlled routing between networks

## Safe test order

1. Keep WiFi or another management link connected.
2. Record the current network configuration.
3. Apply the secondary static configuration only to Ethernet.
4. Ping the gateway.
5. Check ARP.
6. Test public SSH from another network.
7. If it fails, capture evidence and roll back to DHCP if required.

Do not change the working primary wall jack while testing the secondary.

## Evidence to send WeWork

- Device type and built-in Ethernet MAC
- The address received through DHCP
- Static IP, mask, and gateway used in the test
- Gateway packet-loss result
- ARP result
- Which wall jack you used
- A request to confirm switch mapping, VLAN999, and any MAC-registration requirement

That gives WeWork a concrete debugging task instead of “internet does not work.”
