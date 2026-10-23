<script lang="ts">
  // The CPU card's detail, like btop: how many cores and threads, the clock speed and temperature when the machine says, and one bar per thread, threads of one core side by side.
  import { frequencyText, temperatureText, threadGroups, topologyLine } from '../../../lib/cpuView.ts'
  import type { StatsCpu } from '../../../lib/types.ts'

  const FULL = 100
  let { cpu, name = null }: { cpu: StatsCpu; name?: string | null } = $props()
  const groups = $derived(threadGroups(cpu))
  const speed = $derived(frequencyText(cpu.frequency_mhz))
  const heat = $derived(temperatureText(cpu.temperature_celsius))
  /** What the pointer or the keyboard focus is on, written out so it can be read without a tooltip. */
  let pointed = $state('')
</script>

<div class="detail">
  {#if name}<p class="model" data-testid="cpu-model" title={name}>{name}</p>{/if}
  <p class="facts nums">
    <span data-testid="cpu-topology">{topologyLine(cpu)}</span>
    {#if speed}<span data-testid="cpu-frequency">{speed}</span>{/if}
    {#if heat}<span data-testid="cpu-temperature">{heat}</span>{/if}
  </p>
  {#if groups.length > 0}
    <div class="threads" role="group" aria-label="Each thread of the CPU, threads of one core together" data-testid="cpu-threads">
      {#each groups as group (group.core)}
        <div class="core" data-testid="cpu-core">
          {#each group.threads as thread (thread.cpu)}
            <button class="thread" type="button" title={thread.label} aria-label={thread.label} onpointerenter={() => (pointed = thread.label)} onpointerleave={() => (pointed = '')} onfocus={() => (pointed = thread.label)} onblur={() => (pointed = '')}>
              <i style:height="{Math.min(FULL, Math.max(0, thread.percent))}%"></i>
            </button>
          {/each}
        </div>
      {/each}
    </div>
    <p class="pointed nums" aria-live="polite">{pointed || 'Point at a bar to read one thread.'}</p>
  {/if}
</div>

<style>
  .detail { display: grid; gap: 8px; min-width: 0; }
  .model { margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .facts { margin: 0; display: flex; flex-wrap: wrap; gap: 2px 16px; font-family: var(--mono); font-size: 12px; color: var(--m60); }
  .facts span:first-child { font-weight: 700; color: var(--text); }
  .threads { display: flex; flex-wrap: wrap; gap: 4px 6px; max-height: 150px; overflow-y: auto; }
  .core { display: flex; gap: 1px; padding: 2px; border: 1px solid var(--line); background: var(--surface); }
  .thread { display: flex; align-items: flex-end; width: 9px; height: 34px; padding: 0; border: 0; border-radius: 0; background: var(--surface-2); cursor: default; }
  .thread i { display: block; width: 100%; background: var(--accent-mark); }
  .pointed { margin: 0; min-height: 1.3em; font-family: var(--mono); font-size: 11px; color: var(--m60); }
</style>
