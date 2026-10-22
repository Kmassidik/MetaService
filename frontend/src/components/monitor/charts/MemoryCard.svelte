<script lang="ts">
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { memoryChart } from '../../../lib/chartSeries.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'
  import { formatBytes } from '../../../lib/stats.ts'
  import type { StatsMemory } from '../../../lib/types.ts'

  const HINT = 'Cached memory holds recently used files and is handed back when a program needs it. Free memory is what nobody uses.'

  let { points, memory, intervalSeconds }: { points: readonly LivePoint[]; memory: StatsMemory; intervalSeconds: number } = $props()
</script>

<MetricCard label="Memory" hint={HINT}>
  <p class="big nums" data-testid="memory-used">{formatBytes(memory.used_bytes)} <small>of {formatBytes(memory.total_bytes)}</small></p>
  <TimeChart model={memoryChart(points)} label="Memory usage" {intervalSeconds} />
</MetricCard>

<style>
  .big { margin: 0; font-family: var(--mono); font-size: 20px; font-weight: 700; }
  .big small { font-size: 12px; font-weight: 400; color: var(--m60); }
</style>
