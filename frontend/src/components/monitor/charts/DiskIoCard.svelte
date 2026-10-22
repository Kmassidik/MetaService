<script lang="ts">
  // Disk read and write speed. A computer that gives no disk speed says so plainly instead of drawing zeros.
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { diskChart } from '../../../lib/chartSeries.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'

  let { points, intervalSeconds }: { points: readonly LivePoint[]; intervalSeconds: number } = $props()
  const model = $derived(diskChart(points))
</script>

<MetricCard label="Disk speed">
  {#if model}
    <TimeChart {model} label="Disk speed" {intervalSeconds} />
  {:else}
    <p class="none" data-testid="disk-io-none">Not available on this computer.</p>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
</style>
