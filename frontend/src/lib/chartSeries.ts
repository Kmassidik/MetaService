// What each Live chart draws, worked out from the points: which series, in what order, in which colour, on which scale, with which words. Pure functions, no DOM.
import { niceBytesTicks, niceTicks } from './charts.ts'
import { column, type LivePoint } from './liveSeries.ts'
import { formatBytes } from './stats.ts'
import type { StatsBreakdown } from './types.ts'

/** The colour tokens of the series, in palette.css as `--chart-<name>`. */
export type ChartColour = 'green' | 'red' | 'purple' | 'orange' | 'olive' | 'ink' | 'teal' | 'blue' | 'navy'
export type DashStyle = 'solid' | 'dashed' | 'dotted'

export interface SeriesSpec {
  key: string
  name: string
  colour: ChartColour
  /** A line pattern besides the colour, so lines are told apart without colour. */
  dash: DashStyle
  values: (number | null)[]
  format: (value: number) => string
  /** False for a row that only the legend lists (the free memory is the empty space above the stack). */
  drawn: boolean
}

export interface ChartModel {
  times: number[]
  series: SeriesSpec[]
  /** Series are piled on each other (areas) instead of drawn as separate lines. */
  stacked: boolean
  /** The top of the y axis and its tick values. */
  ceiling: number
  ticks: number[]
  axisLabel: (value: number) => string
}

const TICK_COUNT = 4
const CPU_FLOOR_PERCENT = 10
const LOAD_FLOOR = 0.5
const RATE_FLOOR_BYTES = 10 * 1024
const PERCENT_DECIMALS = 1
const LOAD_DECIMALS = 2

const percent = (value: number): string => `${value.toFixed(PERCENT_DECIMALS)}%`
const rate = (value: number): string => `${formatBytes(value)}/s`
const loadText = (value: number): string => value.toFixed(LOAD_DECIMALS)
const wholePercent = (value: number): string => `${Math.round(value)}%`

interface BreakdownState { key: keyof StatsBreakdown; name: string; colour: ChartColour }

/** The order of the stack, bottom to top: the work first, then the waiting. The idle share is not drawn: it is the empty space above. */
const CPU_STATES: readonly BreakdownState[] = [
  { key: 'user', name: 'user', colour: 'green' }, { key: 'system', name: 'system', colour: 'red' }, { key: 'nice', name: 'nice', colour: 'purple' },
  { key: 'irq', name: 'irq', colour: 'orange' }, { key: 'softirq', name: 'softirq', colour: 'olive' }, { key: 'iowait', name: 'iowait', colour: 'ink' }, { key: 'steal', name: 'steal', colour: 'teal' },
]

function series(key: string, name: string, colour: ChartColour, dash: DashStyle, values: (number | null)[], format: (value: number) => string, drawn = true): SeriesSpec {
  return { key, name, colour, dash, values, format, drawn }
}

const times = (points: readonly LivePoint[]): number[] => points.map((point) => point.t)

function stackTop(layers: readonly SeriesSpec[], length: number): number {
  const tops = Array.from({ length }, (_, index) => layers.reduce((sum, one) => sum + (one.values[index] ?? 0), 0))
  return Math.max(0, ...tops)
}

/** CPU use by state, stacked. A helper that gives no breakdown (an older one) gets one series: the total. */
export function cpuChart(points: readonly LivePoint[]): ChartModel {
  const present = CPU_STATES.filter((state) => points.some((point) => point.breakdown?.[state.key] !== undefined))
  const layers: SeriesSpec[] = present.length > 0
    ? present.map((state) => series(state.key, state.name, state.colour, 'solid', column(points, (point) => point.breakdown?.[state.key] ?? null), percent))
    : [series('total', 'in use', 'green', 'solid', column(points, (point) => point.cpu), percent)]
  const ticks = niceTicks(Math.max(CPU_FLOOR_PERCENT, stackTop(layers, points.length)), TICK_COUNT)
  return { times: times(points), series: layers, stacked: true, ceiling: ticks[ticks.length - 1] ?? CPU_FLOOR_PERCENT, ticks, axisLabel: wholePercent }
}

const LOADS: readonly { name: string; colour: ChartColour; dash: DashStyle; index: 0 | 1 | 2 }[] = [
  { name: '1m', colour: 'blue', dash: 'solid', index: 0 }, { name: '5m', colour: 'purple', dash: 'dashed', index: 1 }, { name: '15m', colour: 'navy', dash: 'dotted', index: 2 },
]

/** The load average over 1, 5 and 15 minutes as lines. */
export function loadChart(points: readonly LivePoint[]): ChartModel {
  const lines = LOADS.map((one) => series(one.name, one.name, one.colour, one.dash, column(points, (point) => point.load?.[one.index] ?? null), loadText))
  const top = Math.max(LOAD_FLOOR, ...lines.flatMap((one) => one.values.filter((value): value is number => value !== null)))
  const ticks = niceTicks(top, TICK_COUNT)
  return { times: times(points), series: lines, stacked: false, ceiling: ticks[ticks.length - 1] ?? LOAD_FLOOR, ticks, axisLabel: loadText }
}

/** Memory in use and cached, stacked, up to the total. What is left is free: listed in the legend, not drawn. */
export function memoryChart(points: readonly LivePoint[]): ChartModel {
  const total = points.reduce((top, point) => Math.max(top, point.memTotal), 0)
  const layers = [
    series('used', 'used', 'blue', 'solid', column(points, (point) => point.memUsed), formatBytes),
    series('cached', 'cached', 'teal', 'solid', column(points, (point) => point.memCached), formatBytes),
    series('free', 'free', 'ink', 'solid', column(points, (point) => Math.max(0, point.memTotal - point.memUsed - point.memCached)), formatBytes, false),
  ]
  const { ticks } = niceBytesTicks(total, TICK_COUNT)
  return { times: times(points), series: layers, stacked: true, ceiling: ticks[ticks.length - 1] ?? 1, ticks, axisLabel: formatBytes }
}

function rateChart(points: readonly LivePoint[], lines: SeriesSpec[]): ChartModel {
  const top = Math.max(RATE_FLOOR_BYTES, ...lines.flatMap((one) => one.values.filter((value): value is number => value !== null)))
  const { ticks } = niceBytesTicks(top, TICK_COUNT)
  return { times: times(points), series: lines, stacked: false, ceiling: ticks[ticks.length - 1] ?? RATE_FLOOR_BYTES, ticks, axisLabel: rate }
}

/** Disk read and write speed. Null when the helper gives none (the card says so). */
export function diskChart(points: readonly LivePoint[]): ChartModel | null {
  if (!points.some((point) => point.diskRead !== null || point.diskWrite !== null)) return null
  return rateChart(points, [
    series('read', 'reads', 'teal', 'solid', column(points, (point) => point.diskRead), rate),
    series('write', 'writes', 'orange', 'dashed', column(points, (point) => point.diskWrite), rate),
  ])
}

/** Network speed in and out, on an axis that fits what was seen. */
export function networkChart(points: readonly LivePoint[]): ChartModel {
  return rateChart(points, [
    series('in', 'in', 'blue', 'solid', column(points, (point) => point.netIn), rate),
    series('out', 'out', 'orange', 'dashed', column(points, (point) => point.netOut), rate),
  ])
}
