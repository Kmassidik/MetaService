<script lang="ts">
  import Sparkline from './Sparkline.svelte'
  import { formatBytes, memorySegments } from '../../lib/stats.ts'
  import type { StatsMemory } from '../../lib/types.ts'

  let { memory, history }: { memory: StatsMemory; history: readonly (number | null)[] } = $props()
  const parts = $derived(memorySegments(memory))
  const FULL = 100
</script>

<section class="block" aria-label="Memory">
  <h3>Memory</h3>
  <div class="big nums" data-testid="memory-used">{formatBytes(memory.used_bytes)} <small>of {formatBytes(memory.total_bytes)}</small></div>
  <span class="stack" role="img" aria-label="Memory used, cached and free"><i class="used" style:width="{parts.used}%"></i><i class="cached" style:width="{parts.cached}%"></i></span>
  <dl class="legend">
    <div><dt><i class="used"></i>Used</dt><dd class="nums">{formatBytes(memory.used_bytes)}</dd></div>
    <div><dt><i class="cached"></i>Cached</dt><dd class="nums">{formatBytes(memory.cached_bytes)}</dd></div>
    <div><dt><i class="free"></i>Free</dt><dd class="nums">{formatBytes(memory.free_bytes)}</dd></div>
    {#if memory.swap_total_bytes > 0}<div><dt>Swap</dt><dd class="nums">{formatBytes(memory.swap_used_bytes)} / {formatBytes(memory.swap_total_bytes)}</dd></div>{/if}
  </dl>
  <Sparkline values={history} ceiling={FULL} label="Memory in use over the last minutes" />
</section>

<style>
  .block { display: grid; gap: 8px; align-content: start; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .big { font-family: var(--mono); font-size: 24px; font-weight: 700; }
  .big small { font-size: 12px; font-weight: 400; color: var(--m60); }
  .stack { display: flex; height: 7px; background: var(--gray2); border: 1px solid var(--gray); overflow: hidden; }
  .stack i { display: block; height: 100%; }
  i.used { background: var(--green); }
  i.cached { background: #9ee8bd; }
  i.free { background: var(--gray2); border: 1px solid var(--gray); }
  .legend { margin: 0; display: grid; gap: 2px; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .legend > div { display: flex; justify-content: space-between; gap: 8px; }
  .legend dt { display: flex; align-items: center; gap: 6px; }
  .legend dt i { width: 8px; height: 8px; display: inline-block; }
  .legend dd { margin: 0; color: var(--black); }
</style>
