<script lang="ts">
  // The Network tab of a machine's page: how fast it moves data (Speed), how fast the control server reaches it (Latency) and what it moved today and this month (totals).
  // One range switch (1 hour, 24 hours, 7 days, 30 days) drives the first two. Each card asks for itself while the tab is open, and a machine that is offline keeps its last numbers, greyed like the Live tab.
  import NetworkLatency from './network/NetworkLatency.svelte'
  import NetworkSpeed from './network/NetworkSpeed.svelte'
  import NetworkTotals from './network/NetworkTotals.svelte'
  import { isMachineOffline } from '../../lib/machineOffline.ts'
  import { DEFAULT_NET_RANGE, NET_RANGES, windowOf, type NetRange } from '../../lib/netRange.ts'
  import type { Machine } from '../../lib/types.ts'

  let { machine }: { machine: Machine } = $props()
  let range = $state<NetRange>(DEFAULT_NET_RANGE)
  const grey = $derived(isMachineOffline(machine.state))
</script>

<section class="network" class:grey aria-label="Network" data-testid="network-tab">
  <div class="ranges" role="group" aria-label="Range">
    {#each NET_RANGES as choice (choice)}
      <button type="button" class="btn line sm" class:on={range === choice} aria-pressed={range === choice} onclick={() => (range = choice)}>{windowOf(choice).label}</button>
    {/each}
  </div>
  <div class="band">
    <NetworkSpeed {machine} {range} />
    <NetworkLatency {machine} {range} />
  </div>
  <NetworkTotals {machine} {range} />
</section>

<style>
  .network { display: grid; gap: 16px; }
  .ranges { display: flex; flex-wrap: wrap; gap: 6px; }
  .ranges .btn.on { font-weight: 700; color: var(--text); border-color: var(--accent-mark); }
  .band { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; align-items: stretch; }
  .grey { opacity: 0.45; filter: grayscale(1); }
  @media (max-width: 900px) { .band { grid-template-columns: minmax(0, 1fr); } }
</style>
