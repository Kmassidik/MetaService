<script lang="ts">
  import Bar from './Bar.svelte'
  import MetricCard from './MetricCard.svelte'
  import Sparkline from './Sparkline.svelte'
  import { coreColumns, formatLoad, formatPercent, MEASURING_TEXT } from '../../lib/stats.ts'
  import type { StatsCpu } from '../../lib/types.ts'

  let { cpu, history }: { cpu: StatsCpu; history: readonly (number | null)[] } = $props()
  const cores = $derived(cpu.cores_percent ?? [])
  const FULL = 100
  const LOAD_HINT = 'Load is how many programs are waiting for a turn, averaged over 1, 5 and 15 minutes. Below the core count is fine.'
</script>

<MetricCard label="CPU" hint={LOAD_HINT}>
  <div class="big nums" data-testid="cpu-total">{cpu.total_percent === null ? MEASURING_TEXT : formatPercent(cpu.total_percent)}</div>
  <Bar percent={cpu.total_percent} label="CPU in use" />
  <p class="line nums">{cpu.core_count} cores</p>
  <p class="line nums">load {formatLoad(cpu.load.one)} {formatLoad(cpu.load.five)} {formatLoad(cpu.load.fifteen)}</p>
  {#if cores.length}
    <div class="cores" style:grid-template-columns="repeat({coreColumns(cores.length)}, minmax(0, 1fr))" role="group" aria-label="Each core">
      {#each cores as core, index (index)}
        <span class="core" title="Core {index + 1}: {formatPercent(core)}"><i style:height="{Math.min(FULL, Math.max(0, core))}%"></i></span>
      {/each}
    </div>
  {/if}
  {#snippet graph()}<Sparkline values={history} ceiling={FULL} label="CPU over the last minutes" />{/snippet}
</MetricCard>

<style>
  .big { font-family: var(--mono); font-size: 24px; font-weight: 700; }
  .line { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .cores { display: grid; gap: 3px; max-height: 150px; overflow-y: auto; }
  .core { display: flex; align-items: flex-end; height: 34px; background: var(--surface-2); border: 1px solid var(--line); }
  .core i { display: block; width: 100%; background: var(--accent-mark); }
</style>
