<script lang="ts">
  // The top of the Live tab, like the Grafana page Kurnia showed: five gauges, then the number of programs that run and the traffic. Every one is a bordered card.
  import Gauge from './Gauge.svelte'
  import { gaugeSpecs } from '../../../lib/gauges.ts'
  import { dropsInWindow, type LivePoint } from '../../../lib/liveSeries.ts'
  import { formatBytes, formatRate } from '../../../lib/stats.ts'
  import type { MachineStats } from '../../../lib/types.ts'

  let { stats, points }: { stats: MachineStats; points: readonly LivePoint[] } = $props()
  const gauges = $derived(gaugeSpecs(stats))
  const dropped = $derived(dropsInWindow(points))
  const net = $derived(stats.network)
  const errors = $derived(net.errors_in_total === undefined || net.errors_out_total === undefined ? null : `in ${net.errors_in_total} · out ${net.errors_out_total}`)
</script>

<div class="gauges" data-testid="gauge-row">
  {#each gauges as spec (spec.key)}<Gauge {spec} />{/each}
</div>
<div class="facts" data-testid="gauge-facts">
  {#if stats.process_count !== undefined}
    <section class="card count" aria-label="Processes">
      <h3>Processes</h3>
      <p class="bignum nums" data-testid="process-count">{stats.process_count}</p>
      <p class="sub">programs running</p>
    </section>
  {/if}
  <section class="card traffic" aria-label="Traffic">
    <h3>Traffic</h3>
    <dl class="speeds nums">
      <div><dt>In</dt><dd data-testid="net-down">{formatRate(net.received_bytes_per_second)}</dd></div>
      <div><dt>Out</dt><dd data-testid="net-up">{formatRate(net.sent_bytes_per_second)}</dd></div>
    </dl>
    <p class="sub nums">Since start: {formatBytes(net.received_total_bytes)} in · {formatBytes(net.sent_total_bytes)} out</p>
    {#if dropped !== null}<p class="sub nums" data-testid="net-drops">Dropped packets in the last hour: {dropped}</p>{/if}
    {#if errors !== null}<p class="sub nums" data-testid="net-errors">Packet errors since start: {errors}</p>{/if}
  </section>
</div>

<style>
  .gauges { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 16px; }
  .facts { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 3fr); gap: 16px; }
  .facts:has(> :only-child) { grid-template-columns: minmax(0, 1fr); }
  .card { padding: 14px 16px; gap: 6px; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .bignum { margin: 0; font-family: var(--mono); font-size: 40px; font-weight: 700; line-height: 1; }
  .sub { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .speeds { margin: 0; display: flex; flex-wrap: wrap; gap: 4px 32px; font-family: var(--mono); }
  .speeds > div { display: grid; gap: 2px; }
  .speeds dt { font-size: 11px; color: var(--m60); }
  .speeds dd { margin: 0; font-size: 20px; font-weight: 700; }
  @media (max-width: 900px) { .facts { grid-template-columns: minmax(0, 1fr); } }
</style>
