<script lang="ts">
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { loadChart } from '../../../lib/chartSeries.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'

  const HINT = 'Load is how many programs are waiting for a turn, averaged over 1, 5 and 15 minutes. Below the CPU count is fine.'

  let { points, intervalSeconds }: { points: readonly LivePoint[]; intervalSeconds: number } = $props()
</script>

<MetricCard label="System load" hint={HINT}>
  <TimeChart model={loadChart(points)} label="System load" {intervalSeconds} />
</MetricCard>
