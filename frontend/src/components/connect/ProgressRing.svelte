<script lang="ts">
  // A ring that fills as things get ready or done. It has a text alternative; the numbers inside are plain text too.
  import { RING_RADIUS, RING_SIZE, RING_STROKE, ringArc } from '../../lib/ring.ts'

  let { done, total, alt, tone = 'ready' }: { done: number; total: number; alt: string; tone?: 'ready' | 'optional' | 'blocking' } = $props()
  const arc = $derived(ringArc(done, total))
  const centre = RING_SIZE / 2
</script>

<div class="ring {tone}" role="img" aria-label={alt}>
  <svg viewBox="0 0 {RING_SIZE} {RING_SIZE}" aria-hidden="true">
    <circle class="track" cx={centre} cy={centre} r={RING_RADIUS} stroke-width={RING_STROKE} />
    <circle class="val" cx={centre} cy={centre} r={RING_RADIUS} stroke-width={RING_STROKE} stroke-dasharray="{arc.filled.toFixed(1)} {arc.circle.toFixed(1)}" />
  </svg>
  <div class="txt" aria-hidden="true"><div>{done}<small>of {total}</small></div></div>
</div>

<style>
  .ring { position: relative; width: 92px; height: 92px; flex: none; }
  svg { width: 100%; height: 100%; transform: rotate(-90deg); }
  circle { fill: none; }
  .track { stroke: var(--line); }
  .val { stroke: var(--ok); }
  .optional .val { stroke: var(--warn); }
  .blocking .val { stroke: var(--danger); }
  .txt { position: absolute; inset: 0; display: grid; place-items: center; text-align: center; font-weight: 700; line-height: 1.1; font-size: 20px; }
  small { display: block; font-size: 10px; font-weight: 400; color: var(--m50); font-family: var(--mono); }
</style>
