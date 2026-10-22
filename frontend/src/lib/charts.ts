// The maths of the live charts: scales, nice ticks, paths for lines and stacked areas, the gauge arc, downsampling, the time axis. No DOM, no chart library.

export interface Pt { x: number; y: number }
export type Scale = (value: number) => number
export type GaugeLevel = 'normal' | 'high' | 'critical'

const FULL = 100
const HIGH_FROM = 75
const CRITICAL_FROM = 90
const NICE_STEPS = [1, 2, 2.5, 5, 10]
const KIB = 1024
const MAX_BYTE_UNIT_POWER = 5
const SECONDS_PER_MINUTE = 60
const MINUTE_STEPS = [1, 2, 5, 10, 15, 30, 60, 120, 360, 720]
const DECIMALS = 2
const TWO_DIGITS = 2
const MIN_AREA_POINTS = 2

/** Maps `from` to `a` and `to` to `b`. A flat domain maps everything to `a`. */
export function linearScale(from: number, to: number, a: number, b: number): Scale {
  const span = to - from
  if (span === 0) return () => a
  return (value) => a + ((value - from) / span) * (b - a)
}

/** The step 1, 2, 2.5, 5 or 10 times a power of ten that covers `max` in about `count` steps. */
function niceStep(max: number, count: number): number {
  const raw = max / count
  const power = 10 ** Math.floor(Math.log10(raw))
  const factor = NICE_STEPS.find((step) => step * power >= raw) ?? 10
  return factor * power
}

const hasSomethingToDraw = (max: number): boolean => Number.isFinite(max) && max > 0

function floatSafe(value: number): number {
  return Number(value.toPrecision(12))
}

/** Tick values from 0 up past `max`, evenly spaced on round numbers. Nothing to draw still gives 0 and 1. */
export function niceTicks(max: number, count: number): number[] {
  if (!hasSomethingToDraw(max)) return [0, 1]
  const step = niceStep(max, count)
  const ticks: number[] = []
  for (let value = 0; value < max + step * 0.999; value += step) ticks.push(floatSafe(value))
  return ticks.length >= 2 ? ticks : [0, floatSafe(step)]
}

/** Like niceTicks for bytes: the steps are whole numbers of the biggest 1024 unit that fits, so labels read 250 KB, 500 KB and not 256000. */
export function niceBytesTicks(max: number, count: number): { ticks: number[]; unit: number } {
  if (!hasSomethingToDraw(max)) return { ticks: [0, 1], unit: 1 }
  const power = Math.min(MAX_BYTE_UNIT_POWER, Math.max(0, Math.floor(Math.log(max) / Math.log(KIB))))
  const unit = KIB ** power
  return { ticks: niceTicks(max / unit, count).map((tick) => floatSafe(tick * unit)), unit }
}

/** Pixel positions for a series; a missing value stays missing. */
export function scalePoints(times: readonly number[], values: readonly (number | null)[], x: Scale, y: Scale): (Pt | null)[] {
  return times.map((time, index) => {
    const value = values[index]
    return value === null || value === undefined ? null : { x: x(time), y: y(value) }
  })
}

const fmt = (value: number): string => {
  const rounded = Number(value.toFixed(DECIMALS))
  return String(Object.is(rounded, -0) ? 0 : rounded)
}

/** A line through the points; a missing point lifts the pen. */
export function linePath(points: readonly (Pt | null)[]): string {
  let pen = false
  let path = ''
  for (const point of points) {
    if (point === null) {
      pen = false
      continue
    }
    path += `${pen ? 'L' : 'M'}${fmt(point.x)} ${fmt(point.y)}`
    pen = true
  }
  return path
}

/** Splits a series into runs of consecutive existing points. */
function runsOf<T>(items: readonly (T | null)[]): T[][] {
  const runs: T[][] = []
  let current: T[] = []
  for (const item of items) {
    if (item === null) {
      if (current.length > 0) runs.push(current)
      current = []
      continue
    }
    current.push(item)
  }
  if (current.length > 0) runs.push(current)
  return runs
}

/** One closed shape per run of two or more points where both edges exist: the top edge left to right, the bottom edge back. */
export function areaPaths(upper: readonly (Pt | null)[], lower: readonly (Pt | null)[]): string[] {
  const both = upper.map((top, index) => {
    const bottom = lower[index]
    return top !== null && bottom !== null && bottom !== undefined ? { top, bottom } : null
  })
  return runsOf(both).filter((run) => run.length >= MIN_AREA_POINTS).map((run) => {
    const edge = run.map((item) => item.top).map((point, index) => `${index === 0 ? 'M' : 'L'}${fmt(point.x)} ${fmt(point.y)}`).join('')
    const back = [...run].reverse().map((item) => `L${fmt(item.bottom.x)} ${fmt(item.bottom.y)}`).join('')
    return `${edge}${back}Z`
  })
}

export interface Layer { lower: (number | null)[]; upper: (number | null)[] }

/** Stacks series on top of each other. A missing value is a gap in its own layer and adds nothing to the ones above. */
export function stackSeries(series: readonly (readonly (number | null)[])[]): Layer[] {
  const totals: number[] = []
  return series.map((values) => {
    const lower: (number | null)[] = []
    const upper: (number | null)[] = []
    values.forEach((value, index) => {
      const below = totals[index] ?? 0
      lower.push(below)
      upper.push(value === null ? null : below + value)
      totals[index] = below + (value ?? 0)
    })
    return { lower, upper }
  })
}

/** The half-circle gauge: the grey track and the filled part, in a box `2r` wide and `r` tall. An empty or unknown value has no filled part. */
export function gaugeArc(percent: number | null, radius: number): { track: string; value: string } {
  const track = `M0 ${fmt(radius)}A${fmt(radius)} ${fmt(radius)} 0 0 1 ${fmt(radius * 2)} ${fmt(radius)}`
  if (percent === null || !Number.isFinite(percent) || percent <= 0) return { track, value: '' }
  const angle = Math.PI * (1 - Math.min(FULL, percent) / FULL)
  const x = radius + radius * Math.cos(angle)
  const y = radius - radius * Math.sin(angle)
  return { track, value: `M0 ${fmt(radius)}A${fmt(radius)} ${fmt(radius)} 0 0 1 ${fmt(x)} ${fmt(y)}` }
}

/** Normal, high from 75 percent, critical from 90. A reading that is not there yet is normal. */
export function gaugeLevel(percent: number | null): GaugeLevel {
  if (percent === null) return 'normal'
  if (percent >= CRITICAL_FROM) return 'critical'
  return percent >= HIGH_FROM ? 'high' : 'normal'
}

/** At most `max` values: neighbours are averaged (gaps ignored; a bucket of only gaps stays a gap). A short series is returned as it is. */
export function bucketMeans(values: readonly (number | null)[], max: number): (number | null)[] {
  if (values.length <= max || max < 1) return [...values]
  return Array.from({ length: max }, (_, bucket) => {
    const from = Math.floor((bucket * values.length) / max)
    const to = Math.floor(((bucket + 1) * values.length) / max)
    const present = values.slice(from, to).filter((value): value is number => value !== null)
    return present.length === 0 ? null : present.reduce((sum, value) => sum + value, 0) / present.length
  })
}

/** The time of each bucket of `bucketMeans`: the last time inside it. */
export function bucketTimes(times: readonly number[], max: number): number[] {
  if (times.length <= max || max < 1) return [...times]
  return Array.from({ length: max }, (_, bucket) => times[Math.floor(((bucket + 1) * times.length) / max) - 1] ?? 0)
}

const twoDigits = (value: number): string => String(value).padStart(TWO_DIGITS, '0')

/** "13:05" for a time in seconds since 1970. `offsetMinutes` is the zone as JavaScript gives it (UTC minus local); the browser's own by default. */
export function formatClock(seconds: number, offsetMinutes: number = new Date(seconds * 1000).getTimezoneOffset()): string {
  const local = new Date((seconds - offsetMinutes * SECONDS_PER_MINUTE) * 1000)
  return `${twoDigits(local.getUTCHours())}:${twoDigits(local.getUTCMinutes())}`
}

/** "13:05:20", for the reading at a pointed-at time. */
export function formatClockSeconds(seconds: number, offsetMinutes?: number): string {
  return `${formatClock(seconds, offsetMinutes)}:${twoDigits(((Math.floor(seconds) % SECONDS_PER_MINUTE) + SECONDS_PER_MINUTE) % SECONDS_PER_MINUTE)}`
}

/** Axis labels on round minutes inside [from, to], with the smallest step that gives at most `count` of them. */
export function timeTicks(from: number, to: number, count: number, offsetMinutes?: number): { t: number; label: string }[] {
  if (!(to > from)) return []
  const wanted = MINUTE_STEPS.find((minutes) => (to - from) / (minutes * SECONDS_PER_MINUTE) <= count) ?? MINUTE_STEPS[MINUTE_STEPS.length - 1] ?? 1
  const step = wanted * SECONDS_PER_MINUTE
  const shift = (offsetMinutes ?? new Date(from * 1000).getTimezoneOffset()) * SECONDS_PER_MINUTE
  const ticks: { t: number; label: string }[] = []
  for (let t = Math.ceil((from - shift) / step) * step + shift; t <= to; t += step) ticks.push({ t, label: formatClock(t, offsetMinutes) })
  return ticks
}

/** The index of the time closest to `t`; -1 when there are no times. */
export function nearestIndex(times: readonly number[], t: number): number {
  let best = -1
  let bestGap = Number.POSITIVE_INFINITY
  times.forEach((time, index) => {
    const gap = Math.abs(time - t)
    if (gap < bestGap) {
      best = index
      bestGap = gap
    }
  })
  return best
}

export interface PlotArea { left: number; top: number; width: number; height: number }

const CHAR_WIDTH = 6.6
const AXIS_PADDING = 10
const TOP_MARGIN = 8
const RIGHT_MARGIN = 10
const AXIS_ROW = 22
const MIN_PLOT_WIDTH = 60

/** The box inside a chart where lines are drawn: room on the left for the y labels, below for the time labels. */
export function plotArea(width: number, height: number, yLabels: readonly string[]): PlotArea {
  const labelWidth = Math.max(0, ...yLabels.map((label) => label.length)) * CHAR_WIDTH + AXIS_PADDING
  const plotWidth = Math.max(MIN_PLOT_WIDTH, width - labelWidth - RIGHT_MARGIN)
  return { left: labelWidth, top: TOP_MARGIN, width: plotWidth, height: Math.max(1, height - TOP_MARGIN - AXIS_ROW) }
}
