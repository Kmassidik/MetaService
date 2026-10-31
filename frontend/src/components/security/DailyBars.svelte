<script lang="ts">
  // Failed logins per day for the last 30 days as plain SVG bars. Every bar starts at zero and is as tall as its share of the tallest day (to scale);
  // a day the helper did not count has no bar. The words (axis ends, tallest day) are outside the drawing so they never stretch. Colours are the panel's tokens.
  import { barShares, dayLabel, numberText } from '../../lib/securityRules.ts'

  const VIEW_WIDTH = 300
  const VIEW_HEIGHT = 80
  const BAR_GAP = 0.2

  let { days }: { days: (number | null)[] } = $props()
  const shares = $derived(barShares(days))
  const slot = $derived(VIEW_WIDTH / Math.max(1, days.length))
  const tallest = $derived(Math.max(0, ...days.map((day) => day ?? 0)))
  const summary = $derived(`Failed logins per day, last ${days.length} days, tallest day ${numberText(tallest)}`)
</script>

<figure>
  <div class="top"><span>Per day · tallest {numberText(tallest)}</span></div>
  <svg viewBox="0 0 {VIEW_WIDTH} {VIEW_HEIGHT}" preserveAspectRatio="none" role="img" aria-label={summary} data-testid="security-bars">
    <line x1="0" x2={VIEW_WIDTH} y1={VIEW_HEIGHT - 0.5} y2={VIEW_HEIGHT - 0.5} />
    {#each shares as share, index (index)}
      {#if share !== null}
        <rect x={index * slot + (slot * BAR_GAP) / 2} y={VIEW_HEIGHT - share * VIEW_HEIGHT} width={slot * (1 - BAR_GAP)} height={share * VIEW_HEIGHT}>
          <title>{dayLabel(index, days.length)}: {numberText(days[index] ?? null)} failed</title>
        </rect>
      {/if}
    {/each}
  </svg>
  <div class="ends"><span>{days.length} days ago</span><span>today</span></div>
</figure>

<style>
  figure { margin: 0; display: grid; gap: 4px; min-width: 0; }
  .top, .ends { display: flex; justify-content: space-between; font-family: var(--mono); font-size: 10px; color: var(--m50); }
  svg { width: 100%; height: 96px; display: block; }
  rect { fill: var(--chart-orange); }
  line { stroke: var(--line-strong); stroke-width: 1; vector-effect: non-scaling-stroke; }
</style>
