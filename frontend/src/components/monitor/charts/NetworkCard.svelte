<script lang="ts">
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { networkChart } from '../../../lib/chartSeries.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'

  let { points, intervalSeconds }: { points: readonly LivePoint[]; intervalSeconds: number } = $props()
</script>

<MetricCard label="Network">
  <TimeChart model={networkChart(points)} label="Network speed" {intervalSeconds} />
</MetricCard>
