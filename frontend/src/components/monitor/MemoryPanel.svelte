<script lang="ts">
  import MetricCard from './MetricCard.svelte'
  import Sparkline from './Sparkline.svelte'
  import { formatBytes, memorySegments } from '../../lib/stats.ts'
  import type { StatsMemory } from '../../lib/types.ts'

  let { memory, history }: { memory: StatsMemory; history: readonly (number | null)[] } = $props()
  const parts = $derived(memorySegments(memory))
  const FULL = 100
  const CACHED_HINT = 'Cached memory holds recently used files and is handed back when a program needs it.'
  const SWAP_HINT = 'Swap is disk space used as slow memory when the real memory runs short.'
  const hint = $derived(memory.swap_total_bytes > 0 ? `${CACHED_HINT} ${SWAP_HINT}` : CACHED_HINT)
</script>

<MetricCard label="Memory" {hint}>
  <div class="big nums" data-testid="memory-used">{formatBytes(memory.used_bytes)} <small>of {formatBytes(memory.total_bytes)}</small></div>
  <span class="stack" role="img" aria-label="Memory used, cached and free"><i class="used" style:width="{parts.used}%"></i><i class="cached" style:width="{parts.cached}%"></i></span>
  <p class="line nums"><span><i class="used"></i>Used {formatBytes(memory.used_bytes)}</span><span><i class="cached"></i>Cached {formatBytes(memory.cached_bytes)}</span></p>
  <p class="line nums">
    <span><i class="free"></i>Free {formatBytes(memory.free_bytes)}</span>
    {#if memory.swap_total_bytes > 0}<span>Swap {formatBytes(memory.swap_used_bytes)} / {formatBytes(memory.swap_total_bytes)}</span>{/if}
  </p>
  {#snippet graph()}<Sparkline values={history} ceiling={FULL} label="Memory in use over the last minutes" />{/snippet}
</MetricCard>

<style>
  .big { font-family: var(--mono); font-size: 24px; font-weight: 700; }
  .big small { font-size: 12px; font-weight: 400; color: var(--m60); }
  .stack { display: flex; height: 7px; background: var(--surface-2); border: 1px solid var(--line); overflow: hidden; }
  .stack i { display: block; height: 100%; }
  i.used { background: var(--accent-mark); }
  i.cached { background: var(--accent-soft); }
  i.free { background: var(--surface-2); border: 1px solid var(--line); }
  .line { margin: 0; display: flex; flex-wrap: wrap; gap: 2px 14px; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .line span { display: inline-flex; align-items: center; gap: 6px; }
  .line i { width: 8px; height: 8px; display: inline-block; }
</style>
