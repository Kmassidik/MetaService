// The chart of failed logins per day: one small chart for each watched machine, all on the same scale (the tallest day of any machine), every bar starting at zero.
// A day the parent has no count for has no bar; it is never drawn as zero. Pure functions.
import { RANGE_DAYS, type DailyFailed, type SecurityRange } from './securityTypes.ts'
import { isMacOs, type MachineInfo } from './securityView.ts'

const DAY_MS = 86_400_000
const DAY_TEXT_LENGTH = 10
/** The chart always shows at least this many days, so a 24 h range is still a picture. */
export const MIN_CHART_DAYS = 7

export interface ChartSeries {
  id: string
  name: string
  /** True for a Mac: its days count SSH connections, not failed logins. */
  connections: boolean
  /** Failed logins on each day, the oldest first and today last; null for a day with no count. */
  days: (number | null)[]
  total: number
}

export interface ChartData {
  /** The day of each bar, YYYY-MM-DD (UTC), oldest first. */
  labels: string[]
  series: ChartSeries[]
  /** The tallest day of any machine: the top of every chart. */
  tallest: number
}

/** The days a chart for this range covers, ending today (UTC). */
export function chartDays(range: SecurityRange, now: number): string[] {
  const count = Math.max(MIN_CHART_DAYS, RANGE_DAYS[range])
  return Array.from({ length: count }, (_, index) => new Date(now - (count - 1 - index) * DAY_MS).toISOString().slice(0, DAY_TEXT_LENGTH))
}

/** The series of the machines that are watched and have at least one counted day in the range. */
export function chartData(daily: DailyFailed[], watched: MachineInfo[], range: SecurityRange, now: number): ChartData {
  const labels = chartDays(range, now)
  const series = watched.map((info) => {
    const days = labels.map((label) => daily.find((point) => point.machine === info.id && point.day === label)?.failed ?? null)
    return { id: info.id, name: info.name, connections: isMacOs(info.os), days, total: days.reduce<number>((sum, day) => sum + (day ?? 0), 0) }
  }).filter((one) => one.days.some((day) => day !== null))
  const tallest = Math.max(0, ...series.flatMap((one) => one.days.map((day) => day ?? 0)))
  return { labels, series, tallest }
}

/** A bar's height as a share of the tallest day, 0 to 1; no bar (null) for a day with no count. */
export const barShare = (day: number | null, tallest: number): number | null => (day === null ? null : day / Math.max(1, tallest))
