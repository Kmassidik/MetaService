<script lang="ts">
  // CPU use by state over the last hour, then what the processor is made of (cores and threads) and one bar per thread.
  import CpuDetail from './CpuDetail.svelte'
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { cpuChart } from '../../../lib/chartSeries.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'
  import type { StatsCpu } from '../../../lib/types.ts'

  const HINT = 'CPU use over the last hour, split by what the processor was busy with: user is programs, system is the operating system, nice is low-priority programs, iowait is waiting for the disk.'

  let { points, cpu, intervalSeconds }: { points: readonly LivePoint[]; cpu: StatsCpu; intervalSeconds: number } = $props()
</script>

<MetricCard label="CPU" hint={HINT}>
  <TimeChart model={cpuChart(points)} label="CPU usage" {intervalSeconds} />
  <CpuDetail {cpu} />
</MetricCard>
