<script>
  import { usedPercent } from '../lib/format.js'

  let { label, free, total, format } = $props()
  const percent = $derived(usedPercent(free, total))
</script>

<div class="meter">
  <span class="mlabel">{label}</span>
  {#if percent === null}
    <span class="nums">–</span>
  {:else}
    <meter min="0" max="100" low="70" high="90" optimum="10" value={percent} aria-label="{label} used"></meter>
    <span class="nums val"><b>{format(free)}</b> free of {format(total)}</span>
  {/if}
</div>

<style>
  .meter { display: grid; gap: 4px; min-width: 0; }
  .mlabel { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.12em; color: var(--m40); }
  .val { font-family: var(--mono); font-size: 11px; color: var(--m60); }
  .val b { color: var(--black); }
  meter { width: 100%; height: 7px; background: var(--gray2); border: 1px solid var(--gray); }
  meter::-webkit-meter-bar { background: var(--gray2); border: 0; height: 7px; }
  meter::-webkit-meter-optimum-value { background: var(--green); }
  meter::-webkit-meter-suboptimum-value { background: var(--warn); }
  meter::-webkit-meter-even-less-good-value { background: var(--red, #c0392b); }
</style>
