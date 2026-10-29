<script lang="ts">
  // Real host memory from the helper. This includes managed VMs, external services and the OS; it is not a placement budget.
  import { formatBytes, formatPercent, percentOf } from '../../lib/stats.ts'
  import type { MachineStats } from '../../lib/types.ts'

  let { stats, failure = '' }: { stats: MachineStats | null; failure?: string } = $props()

  const total = $derived(stats?.memory.total_bytes ?? 0)
  const used = $derived(stats?.memory.used_bytes ?? 0)
  const cached = $derived(stats?.memory.cached_bytes ?? 0)
  const free = $derived(stats?.memory.free_bytes ?? 0)
  const other = $derived(Math.max(0, total - used - cached - free))
  const width = (part: number) => `${percentOf(part, total)}%`
</script>

<section class="real-memory" aria-labelledby="real-memory-title">
  <div class="memory-head">
    <h2 id="real-memory-title">Machine memory</h2>
    <span class="muted">Real machine reading · includes VMs, external services and the OS</span>
  </div>
  {#if stats}
    <div class="memory-total"><b>{formatPercent(percentOf(used, total))} used</b><span>{formatBytes(used)} of {formatBytes(total)}</span></div>
    <div class="memory-bar" role="img" aria-label="Used {formatBytes(used)}, cache {formatBytes(cached)}, free {formatBytes(free)}, other {formatBytes(other)}">
      <i class="used" style:width={width(used)}></i><i class="cached" style:width={width(cached)}></i><i class="free" style:width={width(free)}></i><i class="other" style:width={width(other)}></i>
    </div>
    <dl class="memory-key">
      <div><dt><i class="used"></i>Used</dt><dd>{formatBytes(used)}</dd></div>
      <div><dt><i class="cached"></i>Cache</dt><dd>{formatBytes(cached)}</dd></div>
      <div><dt><i class="free"></i>Free</dt><dd>{formatBytes(free)}</dd></div>
      {#if other > 0}<div><dt><i class="other"></i>Other</dt><dd>{formatBytes(other)}</dd></div>{/if}
    </dl>
  {:else}
    <p class="note muted" role="status">Measuring real machine memory…</p>
  {/if}
  {#if failure}<p class="err" role="alert">{failure}</p>{/if}
</section>

<style>
  .real-memory { padding: 0; }
  .memory-head { display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; }
  .memory-head h2 { margin: 0; font-family: var(--mono); font-size: 12px; letter-spacing: .12em; text-transform: uppercase; }
  .memory-head span { font-size: 12px; }
  .memory-total { display: flex; align-items: baseline; gap: 10px; margin-top: 12px; }
  .memory-total b { font-family: var(--mono); font-size: 24px; }
  .memory-total span { color: var(--m60); font-size: 13px; }
  .memory-bar { display: flex; height: 14px; margin: 12px 0; border: 1px solid var(--line-strong); overflow: hidden; }
  .memory-bar i { display: block; height: 100%; }
  .used { background: var(--chart-blue); }
  .cached { background: var(--chart-orange); }
  .free { background: var(--surface-2); }
  .other { background: var(--chart-purple); }
  .memory-key { display: flex; flex-wrap: wrap; gap: 8px 22px; margin: 0; font-family: var(--mono); font-size: 11px; }
  .memory-key div { display: flex; gap: 7px; }
  .memory-key dt { display: flex; align-items: center; gap: 6px; color: var(--m60); }
  .memory-key dt i { display: inline-block; width: 12px; height: 12px; border: 1px solid var(--line-strong); }
  .memory-key dd { margin: 0; font-weight: 700; }
  .note { margin: 12px 0 0; font-size: 13px; }
  .err { margin: 12px 0 0; }
</style>
