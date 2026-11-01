<script lang="ts">
  // Failed logins for the short ranges (1 h to 24 h): one small chart for each watched machine, a bar for every ten minutes, all on the same scale so the bars can be
  // compared across machines. Plain SVG, no library. Every bar starts at zero and is as tall as its share of the tallest bucket; a bucket with no count has no bar.
  // The time axis is in the zone the page shows times in. Colours are the panel's tokens.
  import MetricCard from '../monitor/MetricCard.svelte'
  import { barShare } from '../../lib/securityChart.ts'
  import type { BucketChartData } from '../../lib/securityBuckets.ts'
  import { numberText } from '../../lib/securityRules.ts'
  import { clockLabel } from '../../lib/securityTime.ts'

  const VIEW_WIDTH = 300
  const VIEW_HEIGHT = 60
  const BAR_GAP = 0.15
  const PERCENT = 100
  const CENTRE = 0.5

  let { chart, phrase, zoneLabel }: { chart: BucketChartData; phrase: string; zoneLabel: string } = $props()
  const slot = $derived(VIEW_WIDTH / Math.max(1, chart.starts.length))
  const unit = $derived(`${chart.minutes} minutes`)
  const centre = (index: number): number => ((index + CENTRE) / Math.max(1, chart.starts.length)) * PERCENT
</script>

<MetricCard label="Failed logins per {unit}" hint="One small chart for each machine, all drawn on the same scale, so a tall bar on one machine is really taller than a short bar on another. A bucket with no bar has no count. Each bar is {unit} long and the times under the bars are in the time zone chosen at the top. A Mac counts SSH connections, because macOS does not log who tried.">
  {#if chart.series.length === 0}
    <p class="none" data-testid="chart-empty">No failed logins were counted {phrase}.</p>
  {:else}
    <p class="scale">Tallest bar: {numberText(chart.tallest)} · each bar is {unit} · times in {zoneLabel}</p>
    <div class="multiples" data-testid="bucket-chart">
      {#each chart.series as series (series.id)}
        <figure data-testid="chart-{series.id}">
          <figcaption><b>{series.name}</b><span class="nums">{numberText(series.total)} {series.connections ? 'connections ' : ''}{phrase}</span></figcaption>
          <svg viewBox="0 0 {VIEW_WIDTH} {VIEW_HEIGHT}" preserveAspectRatio="none" role="img" aria-label="{series.name}: {series.connections ? 'SSH connections' : 'failed logins'} per {unit} {phrase}, tallest bar of all machines {numberText(chart.tallest)}">
            <line x1="0" x2={VIEW_WIDTH} y1={VIEW_HEIGHT - 0.5} y2={VIEW_HEIGHT - 0.5} />
            {#each series.counts as count, index (index)}
              {@const share = barShare(count, chart.tallest)}
              {#if share !== null}
                <rect x={index * slot + (slot * BAR_GAP) / 2} y={VIEW_HEIGHT - share * VIEW_HEIGHT} width={slot * (1 - BAR_GAP)} height={share * VIEW_HEIGHT}>
                  <title>{clockLabel(chart.starts[index] ?? 0, 'UTC')} UTC, {unit}: {numberText(count)} {series.connections ? 'connections' : 'failed'}</title>
                </rect>
              {/if}
            {/each}
          </svg>
          <div class="axis" data-testid="bucket-axis" aria-hidden="true">
            {#each chart.ticks as tick (tick.index)}<span style:left="{centre(tick.index)}%">{tick.label}</span>{/each}
          </div>
        </figure>
      {/each}
    </div>
  {/if}
</MetricCard>

<style>
  .none { margin: 0; font-size: 13px; color: var(--m60); }
  .scale { margin: 0; font-family: var(--mono); font-size: 10px; color: var(--m50); }
  .multiples { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px 18px; }
  figure { margin: 0; display: grid; gap: 4px; min-width: 0; }
  figcaption { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; }
  figcaption span { font-family: var(--mono); font-size: 11px; color: var(--m50); }
  svg { width: 100%; height: 64px; display: block; }
  rect { fill: var(--chart-orange); }
  line { stroke: var(--line-strong); stroke-width: 1; vector-effect: non-scaling-stroke; }
  .axis { position: relative; height: 14px; font-family: var(--mono); font-size: 10px; color: var(--m50); }
  .axis span { position: absolute; top: 0; transform: translateX(-50%); white-space: nowrap; }
</style>
