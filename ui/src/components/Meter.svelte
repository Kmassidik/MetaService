<script>
  import { usedPercent } from '../lib/format.js'

  let { label, free, total, format } = $props()
  const percent = $derived(usedPercent(free, total))
</script>

<div class="meter">
  {#if percent === null}
    <span class="nums">–</span>
  {:else}
    <meter min="0" max="100" low="70" high="90" optimum="10" value={percent} aria-label="{label} used"></meter>
    <span class="nums">{format(free)} free <span class="muted">of {format(total)}</span></span>
  {/if}
</div>

<style>
  .meter { display: grid; gap: 3px; min-width: 0; }
  meter { width: 100%; height: 8px; }
  span.nums { font-size: 13px; }
</style>
