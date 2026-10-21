<script lang="ts">
  // Only drawn when the machine could say; the parent leaves the block out otherwise.
  import Bar from './Bar.svelte'
  import { formatBytes, formatPercent, percentOf } from '../../lib/stats.ts'
  import type { StatsGpu } from '../../lib/types.ts'

  let { gpus }: { gpus: StatsGpu[] } = $props()
  const memoryPercent = (gpu: StatsGpu) => (gpu.memory_used_bytes !== null && gpu.memory_total_bytes ? percentOf(gpu.memory_used_bytes, gpu.memory_total_bytes) : null)
</script>

<section class="block" aria-label="GPU">
  <h3>GPU</h3>
  {#each gpus as gpu, index (index)}
    <div class="gpu">
      <div class="top"><span class="name">{gpu.name}</span>{#if gpu.temperature_celsius !== null}<span class="nums">{Math.round(gpu.temperature_celsius)} °C</span>{/if}</div>
      <div class="line"><span>Use</span><span class="nums">{formatPercent(gpu.utilization_percent)}</span></div>
      <Bar percent={gpu.utilization_percent} label="GPU in use" />
      {#if gpu.memory_used_bytes !== null && gpu.memory_total_bytes !== null}
        <div class="line"><span>Memory</span><span class="nums">{formatBytes(gpu.memory_used_bytes)} of {formatBytes(gpu.memory_total_bytes)}</span></div>
        <Bar percent={memoryPercent(gpu)} label="GPU memory in use" />
      {/if}
    </div>
  {/each}
</section>

<style>
  .block { display: grid; gap: 10px; align-content: start; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .gpu { display: grid; gap: 4px; }
  .top, .line { display: flex; justify-content: space-between; gap: 8px; font-family: var(--mono); font-size: 12px; }
  .name { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
  .line { font-size: 11px; color: var(--m60); }
</style>
