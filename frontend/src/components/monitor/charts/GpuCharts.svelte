<script lang="ts">
  // The GPU charts of the Live tab, drawn only for numbers the machine gave: use and memory side by side, then temperature and power (two charts, two units).
  import TimeChart from './TimeChart.svelte'
  import MetricCard from '../MetricCard.svelte'
  import { gpuInfos, gpuMemoryChart, gpuPowerChart, gpuTemperatureChart, gpuUseChart } from '../../../lib/gpuChart.ts'
  import type { LivePoint } from '../../../lib/liveSeries.ts'
  import type { StatsGpu } from '../../../lib/types.ts'

  const USE_HINT = 'How busy each GPU was over the last hour, in percent of what it can do.'
  const MEMORY_HINT = 'Memory in use on each GPU. The top of the chart is the memory the GPU has, when the machine says so.'

  let { gpus, points, intervalSeconds }: { gpus: readonly StatsGpu[]; points: readonly LivePoint[]; intervalSeconds: number } = $props()
  const infos = $derived(gpuInfos(gpus))
  const use = $derived(gpuUseChart(points, infos))
  const memory = $derived(gpuMemoryChart(points, infos))
  const temperature = $derived(gpuTemperatureChart(points, infos))
  const power = $derived(gpuPowerChart(points, infos))
</script>

{#if use || memory}
  <div class="band" class:single={!use || !memory} data-testid="band-gpu-use">
    {#if use}<MetricCard label="GPU use" hint={USE_HINT}><TimeChart model={use} label="GPU use" {intervalSeconds} /></MetricCard>{/if}
    {#if memory}<MetricCard label="GPU memory" hint={MEMORY_HINT}><TimeChart model={memory} label="GPU memory" {intervalSeconds} /></MetricCard>{/if}
  </div>
{/if}
{#if temperature || power}
  <div class="band single" data-testid="band-gpu-heat">
    <MetricCard label="GPU temperature and power">
      {#if temperature}<TimeChart model={temperature} label="GPU temperature" {intervalSeconds} />{/if}
      {#if power}<TimeChart model={power} label="GPU power" {intervalSeconds} />{/if}
    </MetricCard>
  </div>
{/if}

<style>
  .band { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; align-items: stretch; }
  .band.single { grid-template-columns: minmax(0, 1fr); }
  @media (max-width: 900px) { .band { grid-template-columns: minmax(0, 1fr); } }
</style>
