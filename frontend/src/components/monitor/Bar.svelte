<script lang="ts">
  // One horizontal bar. `percent` null draws it empty. `hot` turns it amber when nearly full.
  import { barWidth } from '../../lib/stats.ts'

  let { percent, label }: { percent: number | null; label: string } = $props()
  const hot = $derived(percent !== null && percent >= 90)
</script>

<span class="bar" role="img" aria-label="{label}: {percent === null ? 'measuring' : Math.round(percent) + '%'}"><i class:hot style:width={barWidth(percent)}></i></span>

<style>
  .bar { display: block; height: 7px; background: var(--surface-2); border: 1px solid var(--line); overflow: hidden; }
  i { display: block; height: 100%; background: var(--accent-mark); transition: width 0.4s ease; }
  i.hot { background: var(--warn-line); }
</style>
