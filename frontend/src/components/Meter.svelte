<script lang="ts">
  import { usedPercent } from '../lib/format.ts'
  import Icon from './Icon.svelte'

  let { label, free, total, format, icon = null }: { label: string; free: number | null | undefined; total: number | null | undefined; format: (value: number | null | undefined) => string; icon?: string | null } = $props()
  const percent = $derived(usedPercent(free, total))
</script>

<div class="meter">
  <span class="mlabel">{#if icon}<Icon path={icon} />{/if}{label}</span>
  {#if percent === null}
    <span class="nums">—</span>
  {:else}
    <meter min="0" max="100" low="70" high="90" optimum="10" value={percent} aria-label="{label} used"></meter>
    <span class="nums val"><b>{format(free)}</b> free of {format(total)}</span>
  {/if}
</div>

<style>
  .meter { display: grid; gap: 4px; min-width: 0; }
  .mlabel { display: inline-flex; align-items: center; gap: 6px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.12em; color: var(--m40); }
  .val { font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .val b { color: var(--text); }
  meter { width: 100%; height: 7px; background: var(--surface-2); border: 1px solid var(--line); }
  meter::-webkit-meter-bar { background: var(--surface-2); border: 0; height: 7px; }
  meter::-webkit-meter-optimum-value { background: var(--accent-mark); }
  meter::-webkit-meter-suboptimum-value { background: var(--warn-line); }
  meter::-webkit-meter-even-less-good-value { background: var(--danger); }
</style>
