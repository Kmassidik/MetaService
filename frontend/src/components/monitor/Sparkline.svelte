<script lang="ts">
  // A small history graph drawn as inline SVG. Missing readings leave a gap.
  import { sparkPath } from '../../lib/stats.ts'

  const WIDTH = 120
  const HEIGHT = 28
  let { values, ceiling, label }: { values: readonly (number | null)[]; ceiling: number; label: string } = $props()
  const path = $derived(sparkPath(values, WIDTH, HEIGHT, ceiling))
</script>

<svg class="spark" viewBox="0 0 {WIDTH} {HEIGHT}" preserveAspectRatio="none" role="img" aria-label={label}>
  <line x1="0" y1={HEIGHT} x2={WIDTH} y2={HEIGHT} class="base" />
  {#if path}<path d={path} class="line" vector-effect="non-scaling-stroke" />{/if}
</svg>

<style>
  .spark { width: 100%; height: 100%; min-height: 0; display: block; }
  .base { stroke: var(--line); stroke-width: 1; vector-effect: non-scaling-stroke; }
  .line { fill: none; stroke: var(--accent-d); stroke-width: 1.5; }
</style>
