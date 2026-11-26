// What the Power tab draws, worked out from the points and the newest reading: the fact numbers and the watt lines of the last hour.
// Pure functions, no DOM. A machine (or a helper) that never gave a number has no line and no card, so there is never a flat line of zeros.
import { niceTicks } from './charts.ts'
import type { ChartColour, ChartModel, DashStyle, SeriesSpec } from './chartSeries.ts'
import { column, type LivePoint } from './liveSeries.ts'

const TICK_COUNT = 4
const WATTS_FLOOR = 10
const WATTS_DECIMALS = 1

/** One line of the chart: what to read out of the point, how it is named and drawn. */
interface Rail {
  key: string
  name: string
  colour: ChartColour
  dash: DashStyle
  pick: (point: LivePoint) => number | null
}

/** Machine first, then the parts; a part that never reported is left out, so the legend holds only what was drawn. */
const RAILS: readonly Rail[] = [
  { key: 'machine', name: 'machine', colour: 'ink', dash: 'solid', pick: (point) => point.power },
  { key: 'cpu', name: 'CPU', colour: 'blue', dash: 'solid', pick: (point) => point.cpuPower },
  { key: 'gpu', name: 'GPU', colour: 'orange', dash: 'dashed', pick: (point) => point.gpuPower },
  { key: 'ane', name: 'ANE', colour: 'teal', dash: 'dotted', pick: (point) => point.anePower },
]

const watts = (value: number): string => `${value.toFixed(WATTS_DECIMALS)} W`
const wholeWatts = (value: number): string => `${Math.round(value)} W`

/** The watt lines of the last hour; null when no line has a number. */
export function powerTabChart(points: readonly LivePoint[]): ChartModel | null {
  const lines: SeriesSpec[] = RAILS.flatMap((rail): SeriesSpec[] => {
    const values = column(points, rail.pick)
    return values.every((value) => value === null) ? [] : [{ key: rail.key, name: rail.name, colour: rail.colour, dash: rail.dash, values, format: watts, drawn: true }]
  })
  if (lines.length === 0) return null
  const seen = Math.max(0, ...lines.flatMap((one) => one.values.filter((value): value is number => value !== null)))
  const ticks = niceTicks(Math.max(WATTS_FLOOR, seen), TICK_COUNT)
  return { times: points.map((point) => point.t), series: lines, stacked: false, ceiling: ticks[ticks.length - 1] ?? WATTS_FLOOR, ticks, axisLabel: wholeWatts }
}
