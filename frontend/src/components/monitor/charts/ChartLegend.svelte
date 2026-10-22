<script lang="ts">
  // The legend table of a chart, like Grafana's: a swatch, the name and the value. It shows the newest value, or the value at the time the pointer or the keys point at.
  import type { SeriesSpec } from '../../../lib/chartSeries.ts'

  const SWATCH_WIDTH = 22
  const SWATCH_MIDDLE = 5
  const DASHES: Record<SeriesSpec['dash'], string> = { solid: '', dashed: '6 3', dotted: '1.5 3' }

  /** `index` is the point to read the values at; `when` says which time that is ("now" for the newest). */
  let { series, index, when }: { series: readonly SeriesSpec[]; index: number; when: string } = $props()
  const valueOf = (one: SeriesSpec): string => {
    const value = one.values[index]
    return value === null || value === undefined ? '–' : one.format(value)
  }
</script>

<table class="legend" aria-label="Legend: values {when}">
  <thead><tr><th colspan="2" scope="col">{when}</th></tr></thead>
  <tbody>
    {#each series as one (one.key)}
      <tr>
        <td class="name">
          <svg class="swatch" width={SWATCH_WIDTH} height={SWATCH_MIDDLE * 2} aria-hidden="true">
            {#if one.drawn}
              <line x1="0" x2={SWATCH_WIDTH} y1={SWATCH_MIDDLE} y2={SWATCH_MIDDLE} stroke="var(--chart-{one.colour})" stroke-width="3" stroke-dasharray={DASHES[one.dash]} />
            {:else}
              <rect x="1" y="1" width={SWATCH_WIDTH - 2} height={SWATCH_MIDDLE * 2 - 2} fill="none" stroke="var(--chart-{one.colour})" stroke-width="1" />
            {/if}
          </svg>
          {one.name}
        </td>
        <td class="val nums" data-testid="legend-{one.key}">{valueOf(one)}</td>
      </tr>
    {/each}
  </tbody>
</table>

<style>
  .legend { border-collapse: collapse; font-family: var(--mono); font-size: 11px; min-width: 150px; align-self: start; }
  th { text-align: left; font-weight: 400; color: var(--m50); padding: 0 0 4px; border-bottom: 1px solid var(--line); }
  td { padding: 3px 0; border-bottom: 1px solid var(--surface-2); }
  .name { display: flex; align-items: center; gap: 6px; padding-right: 10px; color: var(--text); }
  .swatch { flex: none; }
  .val { text-align: right; white-space: nowrap; }
</style>
