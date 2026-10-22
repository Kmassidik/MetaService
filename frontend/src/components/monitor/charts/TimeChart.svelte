<script lang="ts">
  // A Grafana-style time chart in inline SVG: stacked areas or lines, grid and y labels, a time axis, and a legend table at the right (below on a narrow card).
  // Pointing at it, or pressing the left and right arrow keys, reads the values at that time. A hidden table gives the same numbers to screen readers.
  import ChartLegend from './ChartLegend.svelte'
  import type { ChartModel, SeriesSpec } from '../../../lib/chartSeries.ts'
  import { areaPaths, bucketMeans, bucketTimes, formatClockSeconds, linePath, linearScale, nearestIndex, plotArea, scalePoints, stackSeries, timeTicks } from '../../../lib/charts.ts'
  import { summarize } from '../../../lib/liveSeries.ts'

  const HEIGHT = 190
  const DEFAULT_WIDTH = 520
  const WINDOW_SECONDS = 3600
  const TICK_SPACING_PX = 90
  const MIN_TICKS = 2
  const MIN_POINTS_TO_DRAW = 2
  const DASHES: Record<SeriesSpec['dash'], string> = { solid: '', dashed: '6 3', dotted: '1.5 3' }
  const AREA_OPACITY = 0.78

  let { model, label, intervalSeconds }: { model: ChartModel; label: string; intervalSeconds: number } = $props()
  let width = $state(DEFAULT_WIDTH)
  /** The point the pointer or the keys point at, as an index into the model's times; null shows the newest. */
  let picked = $state<number | null>(null)

  const area = $derived(plotArea(width, HEIGHT, model.ticks.map(model.axisLabel)))
  const last = $derived(model.times.length - 1)
  const tEnd = $derived(model.times[last] ?? 0)
  const tStart = $derived(tEnd - WINDOW_SECONDS)
  const x = $derived(linearScale(tStart, tEnd, area.left, area.left + area.width))
  const y = $derived(linearScale(0, model.ceiling, area.top + area.height, area.top))
  const drawn = $derived(model.series.filter((one) => one.drawn))
  const hasData = $derived(drawn.some((one) => one.values.filter((value) => value !== null).length >= MIN_POINTS_TO_DRAW))
  const timeLabels = $derived(timeTicks(tStart, tEnd, Math.max(MIN_TICKS, Math.floor(area.width / TICK_SPACING_PX))))
  const reading = $derived(picked ?? last)
  const when = $derived(picked === null ? 'now' : formatClockSeconds(model.times[picked] ?? 0))

  interface Shape { key: string; colour: string; dash: string; areas: string[]; line: string }

  /** Few enough points that none are closer than a pixel. */
  const shapes = $derived.by((): Shape[] => {
    const wanted = Math.max(1, Math.floor(area.width))
    const times = bucketTimes(model.times, wanted)
    const columns = drawn.map((one) => bucketMeans(one.values, wanted))
    const layers = model.stacked ? stackSeries(columns) : []
    return drawn.map((one, index): Shape => {
      const layer = layers[index]
      const top = scalePoints(times, layer ? layer.upper : (columns[index] ?? []), x, y)
      const bottom = layer ? scalePoints(times, layer.lower, x, y) : []
      return { key: one.key, colour: one.colour, dash: DASHES[one.dash], areas: layer ? areaPaths(top, bottom) : [], line: linePath(top) }
    })
  })

  function pick(clientX: number, box: DOMRect) {
    const px = (clientX - box.left) * (width / Math.max(1, box.width))
    const seconds = tStart + ((px - area.left) / area.width) * WINDOW_SECONDS
    const found = nearestIndex(model.times, seconds)
    picked = found < 0 ? null : found
  }

  function onMove(event: PointerEvent) {
    if (event.currentTarget instanceof Element) pick(event.clientX, event.currentTarget.getBoundingClientRect())
  }

  /** The arrow keys move the hidden range control, which says the time and the values to a screen reader. */
  function onSlide(event: Event) {
    if (event.currentTarget instanceof HTMLInputElement) picked = Number(event.currentTarget.value)
  }

  const spoken = $derived(`${when}: ${model.series.map((one) => `${one.name} ${valueText(one, reading)}`).join(', ')}`)

  function valueText(one: SeriesSpec, index: number): string {
    const value = one.values[index]
    return value === null || value === undefined ? 'no reading' : one.format(value)
  }

  const markerX = $derived(picked === null ? null : x(model.times[picked] ?? 0))
</script>

<div class="chart" data-testid="chart-{label}">
  <div class="body">
    <div class="plot" role="presentation" bind:clientWidth={width} onpointermove={onMove} onpointerleave={() => (picked = null)}>
      <svg viewBox="0 0 {width} {HEIGHT}" height={HEIGHT} aria-hidden="true">
        {#each model.ticks as tick (tick)}
          <line class="grid" x1={area.left} x2={area.left + area.width} y1={y(tick)} y2={y(tick)} />
          <text class="ylabel" x={area.left - 6} y={y(tick)} text-anchor="end" dominant-baseline="middle">{model.axisLabel(tick)}</text>
        {/each}
        {#each timeLabels as tick (tick.t)}
          <line class="tick" x1={x(tick.t)} x2={x(tick.t)} y1={area.top + area.height} y2={area.top + area.height + 4} />
          <text class="xlabel" x={x(tick.t)} y={area.top + area.height + 16} text-anchor="middle">{tick.label}</text>
        {/each}
        {#each shapes as shape (shape.key)}
          {#each shape.areas as path, part (part)}<path class="area" d={path} fill="var(--chart-{shape.colour})" fill-opacity={AREA_OPACITY} />{/each}
          <path class="line" d={shape.line} stroke="var(--chart-{shape.colour})" stroke-dasharray={shape.dash} />
        {/each}
        {#if markerX !== null}<line class="marker" x1={markerX} x2={markerX} y1={area.top} y2={area.top + area.height} />{/if}
      </svg>
      <input class="keys" type="range" min="0" max={Math.max(0, last)} step="1" value={reading} aria-label="{label}: move through the last hour with the arrow keys" aria-valuetext={spoken} oninput={onSlide} onblur={() => (picked = null)} />
      {#if !hasData}<p class="empty" role="status">Collecting numbers… the chart fills in as readings come.</p>{/if}
    </div>
    <ChartLegend series={model.series} index={reading} {when} />
  </div>
  <p class="caption nums">per {intervalSeconds} seconds · last hour</p>
  <div class="sr-only">
  <table>
    <caption>{label}: newest, lowest, highest and average over the last hour</caption>
    <thead><tr><th scope="col">Series</th><th scope="col">Newest</th><th scope="col">Lowest</th><th scope="col">Highest</th><th scope="col">Average</th></tr></thead>
    <tbody>
      {#each model.series as one (one.key)}
        {@const sum = summarize(one.values)}
        <tr>
          <th scope="row">{one.name}</th>
          {#each [sum.latest, sum.min, sum.max, sum.mean] as value, column (column)}<td>{value === null ? 'no reading' : one.format(value)}</td>{/each}
        </tr>
      {/each}
    </tbody>
  </table>
  </div>
</div>

<style>
  .chart { container-type: inline-size; display: grid; gap: 4px; min-width: 0; }
  .body { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 14px; align-items: start; }
  .plot { position: relative; min-width: 0; overflow: hidden; }
  svg { display: block; width: 100%; }
  .plot:focus-within { outline: 2px solid var(--focus); outline-offset: 2px; }
  .keys { position: absolute; left: 0; top: 0; width: 1px; height: 1px; margin: 0; opacity: 0; pointer-events: none; }
  .grid { stroke: var(--line); stroke-width: 1; }
  .tick { stroke: var(--m50); stroke-width: 1; }
  .ylabel, .xlabel { font-family: var(--mono); font-size: 10px; fill: var(--m60); }
  .line { fill: none; stroke-width: 1.6; stroke-linejoin: round; }
  .area { stroke: none; }
  .marker { stroke: var(--text); stroke-width: 1; stroke-dasharray: 3 3; }
  .empty { position: absolute; inset: 0 0 22px 0; margin: 0; display: grid; place-items: center; text-align: center; padding: 0 16px; font-size: 12px; color: var(--m60); }
  .caption { margin: 0; text-align: center; font-family: var(--mono); font-size: 11px; color: var(--m60); }
  @container (max-width: 520px) { .body { grid-template-columns: minmax(0, 1fr); } }
</style>
