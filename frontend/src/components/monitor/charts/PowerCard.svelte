<script lang="ts">
  // Whole-machine power draw over the last hour, with the newest reading as a line of facts. The card is drawn only when
  // the machine gave at least one watt; a helper that cannot read power says nothing here instead of drawing zeros.
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { powerChart, powerText } from '../../../lib/powerChart.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'

  const HINT = 'How many watts the whole machine drew over the last hour, as the helper reads it.'

  let { points, intervalSeconds }: { points: readonly LivePoint[]; intervalSeconds: number } = $props()
  const model = $derived(powerChart(points))
</script>

{#if model}
  <MetricCard label="Power" hint={HINT}>
    <p class="now nums" data-testid="power-now">{powerText(points)}</p>
    <TimeChart {model} label="Power" {intervalSeconds} />
  </MetricCard>
{/if}

<style>
  .now { margin: 0; font-family: var(--mono); font-size: 18px; font-weight: 700; line-height: 1.1; color: inherit; }
</style>
