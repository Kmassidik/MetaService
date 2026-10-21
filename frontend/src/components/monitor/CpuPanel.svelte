<script lang="ts">
  import Bar from './Bar.svelte'
  import Sparkline from './Sparkline.svelte'
  import { coreColumns, formatLoad, formatPercent, MEASURING_TEXT } from '../../lib/stats.ts'
  import type { StatsCpu } from '../../lib/types.ts'

  let { cpu, history }: { cpu: StatsCpu; history: readonly (number | null)[] } = $props()
  const cores = $derived(cpu.cores_percent ?? [])
  const FULL = 100
  const LOAD_HINT = 'Load is how many programs are waiting for a turn, averaged over 1, 5 and 15 minutes. Below the core count is fine.'
  let showCores = $state(false)
</script>

<section class="block" aria-label="CPU">
  <h3>CPU</h3>
  <div class="big nums" data-testid="cpu-total">{cpu.total_percent === null ? MEASURING_TEXT : formatPercent(cpu.total_percent)}</div>
  <Bar percent={cpu.total_percent} label="CPU in use" />
  <p class="sub nums">
    {#if cores.length}
      <button class="btn line sm" type="button" aria-expanded={showCores} aria-controls="core-grid" onclick={() => (showCores = !showCores)}>{cpu.core_count} cores {showCores ? '▴' : '▾'}</button>
    {:else}{cpu.core_count} cores{/if}
    · load {formatLoad(cpu.load.one)} {formatLoad(cpu.load.five)} {formatLoad(cpu.load.fifteen)}
  </p>
  <p class="hint">{LOAD_HINT}</p>
  {#if cores.length && showCores}
    <div id="core-grid" class="cores" style:grid-template-columns="repeat({coreColumns(cores.length)}, minmax(0, 1fr))" aria-label="Each core">
      {#each cores as core, index (index)}
        <span class="core" title="Core {index + 1}: {formatPercent(core)}"><i style:height="{Math.min(FULL, Math.max(0, core))}%"></i></span>
      {/each}
    </div>
  {/if}
  <Sparkline values={history} ceiling={FULL} label="CPU over the last minutes" />
</section>

<style>
  .block { display: grid; gap: 8px; align-content: start; min-width: 0; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .big { font-family: var(--mono); font-size: 24px; font-weight: 700; }
  .sub { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .hint { margin: 0; font-size: 12px; color: var(--m50); }
  .cores { display: grid; gap: 3px; }
  .core { display: flex; align-items: flex-end; height: 34px; background: var(--gray2); border: 1px solid var(--gray); }
  .core i { display: block; width: 100%; background: var(--green); }
</style>
