Design reference (from Kurnia's critique + his HTML mock, 2026-11-19). Read before touching MachineMap.svelte again.

What to adopt from the mock into the real Svelte map:
1. Canvas fills available width; zoom controls anchored INSIDE the canvas corner (ours already are — keep).
2. Node cards: white, rounded, shadow, hardware icon, status dot top-right, name + IP label below — we have this; strengthen contrast of the IP label.
3. Edges strictly anchored node-center to node-center (fix any stray segment), protocol badge pill at edge midpoint when zoomed in or hovered.
4. Live traffic: animated packet dots flowing along edges (mesh/ssh/public colored), toggleable "Live Traffic" button.
5. Inspection drawer: slide-over panel on node click — name, role, IP (click-to-copy), os, protocol, latency, cpu/mem, quick actions (SSH shell, Ping with radar ripple animation).
6. Legend + hints tucked INSIDE the canvas as a floating bottom bar, not below the canvas.
7. Search dims non-matching nodes/edges instead of removing them (we filter the array — mock dims; decide: dimming preserves layout context, adopt it).
8. Status pills/legend colors: online #3B7A3E, setup amber, offline gray — map to panel tokens (--ok/--warn/--off).
9. "Re-center Map" button: restore default layout coordinates + reset camera.
10. Ping action: expanding ring ripple on the node.

Panel integration notes:
- Map Svelte tokens not hex colors; mock's palette maps to: brand green → --accent/--ok, amber → --warn, gray → --muted/--off.
- Machine data must come from the real machines prop, NOT hardcoded nodes/latency/load. Latency/load are NOT in Machine type — omit or wire to a real API later; do not fake numbers.
- Search is route-query driven (?q=) — filtering stays in Machines.svelte; Map just dims to unmatched styling.
- Double-click opens detail page (keep), single click opens the inspector drawer (new, replaces table-row select? — table below canvas can stay; drawer is the inspection surface).

## Shipped 2026-11-20
- Full canvas engine swap chosen by Kurnia: `MachineCanvas.svelte` replaces `MachineMap.svelte` (deleted).
- Drawer shows real Machine fields only (address/os/arch/link/helper/ram/cpu/problems) — no invented telemetry.
- Route query `?q=` dims non-matching nodes; `?tab=` picks the view.
- Layout math stays in `machineMap.ts` (buildGraph), covered by machineMap.test.ts.
