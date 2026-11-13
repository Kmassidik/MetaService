<script lang="ts">
  import type { LatencyPoint } from '../lib/latencyParse.ts'
  import { SPARK_HEIGHT, SPARK_WIDTH, sparkline } from '../lib/latencySpark.ts'

  let { points }: { points: LatencyPoint[] } = $props()
  const shape = $derived(sparkline(points))
</script>

<svg class="spark" viewBox="0 0 {SPARK_WIDTH} {SPARK_HEIGHT}" role="img" aria-label="{points.length} readings">
  {#each shape.lines as line (line)}
    <polyline points={line} fill="none" />
  {/each}
  {#each shape.failedX as x, index (index)}
    <line class="lost" x1={x} x2={x} y1="0" y2={SPARK_HEIGHT} />
  {/each}
</svg>

<style>
  .spark { width: 100%; height: 28px; display: block; overflow: visible; }
  polyline { stroke: var(--ok); stroke-width: 1.5; stroke-linejoin: round; }
  .lost { stroke: var(--danger); stroke-width: 1.5; }
</style>
