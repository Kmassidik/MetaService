<script lang="ts">
  // One half-circle gauge in a bordered card. The number is always written in the middle; the colour only says how full it is (moss, amber, red).
  import { gaugeArc } from '../../../lib/charts.ts'
  import type { GaugeSpec } from '../../../lib/gauges.ts'

  const RADIUS = 50
  const STROKE = 12
  const PAD = STROKE / 2 + 1

  let { spec }: { spec: GaugeSpec } = $props()
  const arc = $derived(gaugeArc(spec.percent, RADIUS))
</script>

<section class="card gauge" aria-label={spec.label}>
  <h3>{spec.label}</h3>
  <div class="dial" role="img" aria-label={spec.describe} title={spec.describe}>
    <svg viewBox="{-PAD} {-PAD} {RADIUS * 2 + PAD * 2} {RADIUS + PAD * 2}" aria-hidden="true">
      <path class="track" d={arc.track} stroke-width={STROKE} />
      {#if arc.value}<path class="fill {spec.level}" d={arc.value} stroke-width={STROKE} />{/if}
    </svg>
    <span class="value nums" data-testid="gauge-{spec.key}">{spec.value}</span>
  </div>
  <p class="caption nums">{spec.caption}</p>
</section>

<style>
  .gauge { padding: 12px 12px 14px; gap: 4px; min-width: 0; align-items: center; text-align: center; }
  h3 { margin: 0; font-family: var(--mono); font-size: 11px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--m50); }
  .dial { position: relative; width: 100%; max-width: 170px; }
  svg { display: block; width: 100%; height: auto; }
  path { fill: none; stroke-linecap: butt; }
  .track { stroke: var(--line); }
  .fill.normal { stroke: var(--accent-mark); }
  .fill.high { stroke: var(--warn-line); }
  .fill.critical { stroke: var(--danger); }
  .value { position: absolute; left: 0; right: 0; bottom: 0; font-family: var(--mono); font-size: 18px; font-weight: 700; line-height: 1.1; }
  .caption { margin: 0; font-family: var(--mono); font-size: 11px; color: var(--m60); overflow-wrap: anywhere; }
</style>
