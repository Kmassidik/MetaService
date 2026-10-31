<script lang="ts">
  // Failed logins per day: one small chart for each watched machine, all on the same scale so the bars can be compared across machines. Plain SVG, no library.
  // Every bar starts at zero and is as tall as its share of the tallest day; a day with no count has no bar. Colours are the panel's tokens.
  import MetricCard from '../monitor/MetricCard.svelte'
  import { barShare, type ChartData } from '../../lib/securityChart.ts'
  import { numberText } from '../../lib/securityRules.ts'

  const VIEW_WIDTH = 300
  const VIEW_HEIGHT = 60
  const BAR_GAP = 0.2

  let { chart }: { chart: ChartData } = $props()
  const slot = $derived(VIEW_WIDTH / Math.max(1, chart.labels.length))
  const first = $derived(chart.labels[0] ?? '')
  const last = $derived(chart.labels.at(-1) ?? '')
</script>

<MetricCard label="Failed logins per day" hint="One small chart for each machine, all drawn on the same scale, so a tall bar on one machine is really taller than a short bar on another. A day with no bar has no count.">
  {#if chart.series.length === 0}
    <p class="none" data-testid="chart-empty">No failed logins were counted in this time range.</p>
  {:else}
    <p class="scale">Tallest day: {numberText(chart.tallest)}</p>
    <div class="multiples">
      {#each chart.series as series (series.id)}
        <figure data-testid="chart-{series.id}">
          <figcaption><b>{series.name}</b><span class="nums">{numberText(series.total)} in total</span></figcaption>
          <svg viewBox="0 0 {VIEW_WIDTH} {VIEW_HEIGHT}" preserveAspectRatio="none" role="img" aria-label="{series.name}: failed logins per day, {first} to {last}, tallest day of all machines {numberText(chart.tallest)}">
            <line x1="0" x2={VIEW_WIDTH} y1={VIEW_HEIGHT - 0.5} y2={VIEW_HEIGHT - 0.5} />
            {#each series.days as day, index (index)}
              {@const share = barShare(day, chart.tallest)}
              {#if share !== null}
                <rect x={index * slot + (slot * BAR_GAP) / 2} y={VIEW_HEIGHT - share * VIEW_HEIGHT} width={slot * (1 - BAR_GAP)} height={share * VIEW_HEIGHT}>
                  <title>{chart.labels[index]}: {numberText(day)} failed</title>
                </rect>
              {/if}
            {/each}
          </svg>
        </figure>
      {/each}
    </div>
    <div class="ends"><span>{first}</span><span>{last}</span></div>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .scale, .ends { margin: 0; font-family: var(--mono); font-size: 10px; color: var(--m50); }
  .ends { display: flex; justify-content: space-between; }
  .multiples { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px 18px; }
  figure { margin: 0; display: grid; gap: 4px; min-width: 0; }
  figcaption { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; }
  figcaption span { font-family: var(--mono); font-size: 11px; color: var(--m50); }
  svg { width: 100%; height: 64px; display: block; }
  rect { fill: var(--chart-orange); }
  line { stroke: var(--line-strong); stroke-width: 1; vector-effect: non-scaling-stroke; }
</style>
