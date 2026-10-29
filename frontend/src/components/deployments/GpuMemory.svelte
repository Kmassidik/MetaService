<script lang="ts">
  // The card's memory beside the machine's memory: how much is in use right now (whoever holds it), how much is booked for VMs and not taken yet, and how much is free.
  import { gbText } from '../../lib/gpuLive.ts'
  import type { GpuMemoryParts } from '../../lib/gpuMemory.ts'

  let { parts }: { parts: GpuMemoryParts } = $props()
  const width = (part: number) => `${parts.totalGb > 0 ? (part / parts.totalGb) * 100 : 0}%`
  const percentUsed = $derived(parts.totalGb > 0 ? Math.round((parts.inUseGb / parts.totalGb) * 100) : 0)
</script>

<section class="gpu-memory" aria-labelledby="gpu-memory-title">
  <div class="memory-head">
    <h2 id="gpu-memory-title">GPU memory</h2>
    <span class="muted">{parts.name} · real reading, whoever holds it</span>
  </div>
  <div class="memory-total"><b>{percentUsed}% used</b><span>{gbText(parts.inUseGb)} of {gbText(parts.totalGb)}</span></div>
  <div class="memory-bar" role="img" aria-label="In use {gbText(parts.inUseGb)}, booked and not used yet {gbText(parts.bookedIdleGb)}, free {gbText(parts.freeGb)}">
    <i class="used" style:width={width(parts.inUseGb)}></i><i class="booked" style:width={width(parts.bookedIdleGb)}></i><i class="free" style:width={width(parts.freeGb)}></i>
  </div>
  <dl class="memory-key">
    <div><dt><i class="used"></i>In use</dt><dd>{gbText(parts.inUseGb)}</dd></div>
    {#if parts.bookedIdleGb > 0}<div><dt><i class="booked"></i>Booked, not used yet</dt><dd>{gbText(parts.bookedIdleGb)}</dd></div>{/if}
    <div><dt><i class="free"></i>Free</dt><dd>{gbText(parts.freeGb)}</dd></div>
  </dl>
  {#if parts.programs.length > 0}
    <ul class="programs" aria-label="Programs holding GPU memory">
      {#each parts.programs as program, at (at)}<li><span class="pname">{program.name}</span><span>{gbText(program.gb)}</span></li>{/each}
    </ul>
  {/if}
</section>

<style>
  .gpu-memory { padding: 16px 0 0; border-top: 1px solid var(--line); }
  .memory-head { display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; }
  .memory-head h2 { margin: 0; font-family: var(--mono); font-size: 12px; letter-spacing: .12em; text-transform: uppercase; }
  .memory-head span { font-size: 12px; }
  .memory-total { display: flex; align-items: baseline; gap: 10px; margin-top: 12px; }
  .memory-total b { font-family: var(--mono); font-size: 24px; }
  .memory-total span { color: var(--m60); font-size: 13px; }
  .memory-bar { display: flex; height: 14px; margin: 12px 0; border: 1px solid var(--line-strong); overflow: hidden; }
  .memory-bar i { display: block; height: 100%; }
  .used { background: var(--chart-blue); }
  .booked { background: repeating-linear-gradient(135deg, var(--warn-bg) 0 4px, var(--warn-line) 4px 5px); }
  .free { background: var(--surface-2); }
  .memory-key { display: flex; flex-wrap: wrap; gap: 8px 22px; margin: 0; font-family: var(--mono); font-size: 11px; }
  .memory-key div { display: flex; gap: 7px; }
  .memory-key dt { display: flex; align-items: center; gap: 6px; color: var(--m60); }
  .memory-key dt i { display: inline-block; width: 12px; height: 12px; border: 1px solid var(--line-strong); }
  .memory-key dd { margin: 0; font-weight: 700; }
  .programs { list-style: none; margin: 12px 0 0; padding: 10px 0 0; border-top: 1px solid var(--line); display: grid; gap: 4px; font-family: var(--mono); font-size: 11px; }
  .programs li { display: flex; justify-content: space-between; gap: 10px; }
  .pname { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--m70); }
</style>
