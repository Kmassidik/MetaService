// The whole-machine power chart of the Live tab: one line of watts over the last hour. Pure functions, no DOM.
// A machine that never gave a watt has no line (the card is not drawn), so there is never a flat line of zeros.
import { niceTicks } from './charts.ts'
import type { ChartModel, SeriesSpec } from './chartSeries.ts'
import { column, type LivePoint } from './liveSeries.ts'

const TICK_COUNT = 4
const POWER_FLOOR_WATTS = 10
const POWER_DECIMALS = 1

/** "102.3 W"; the axis labels round it. */
const watts = (value: number): string => `${value.toFixed(POWER_DECIMALS)} W`
const wholeWatts = (value: number): string => `${Math.round(value)} W`

/** Power draw of the whole machine, in watts; null when the helper gave none (an older helper). */
export function powerChart(points: readonly LivePoint[]): ChartModel | null {
  const values = column(points, (point) => point.power)
  if (values.every((value) => value === null)) return null
  const line: SeriesSpec = { key: 'power', name: 'power', colour: 'orange', dash: 'solid', values, format: watts, drawn: true }
  const ticks = niceTicks(Math.max(POWER_FLOOR_WATTS, ...values.filter((value): value is number => value !== null)), TICK_COUNT)
  return { times: points.map((point) => point.t), series: [line], stacked: false, ceiling: ticks[ticks.length - 1] ?? POWER_FLOOR_WATTS, ticks, axisLabel: wholeWatts }
}

/** The newest power reading as "102.3 W", or "—" when the machine did not give one. */
export function powerText(points: readonly LivePoint[]): string {
  for (let index = points.length - 1; index >= 0; index -= 1) {
    const value = points[index]?.power
    if (value !== null && value !== undefined) return watts(value)
  }
  return '—'
}
