// Geometry and labels of the daily traffic chart: where each download and upload bar sits, scaled to the biggest day, and what each day is called.
// The office day starts at local midnight in UTC+7; the server already splits the days that way. Pure: no DOM, so it is easy to test.
import { DAY_SECONDS, type UsageDay } from './usageParse.ts'

export const OFFICE_UTC_OFFSET_MINUTES = 420
export const CHART_WIDTH = 600
export const CHART_HEIGHT = 160
/** Room under the bars for the day labels. */
export const LABEL_ROOM = 18
/** The share of one day's slot that the pair of bars fills. */
const PAIR_SHARE = 0.7
const SECONDS_PER_MINUTE = 60
const MS_PER_SECOND = 1000
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const

export interface DayBar {
  /** The day this pair of bars shows. */
  day: UsageDay
  /** Left edge of the download bar. */
  x: number
  /** Width of one bar of the pair. */
  width: number
  /** Height of the download bar. */
  inHeight: number
  /** Height of the upload bar. */
  outHeight: number
  /** Left edge of the upload bar. */
  outX: number
}

/** The start of today in the office time zone, in epoch seconds, for a moment given in epoch milliseconds. */
export function officeTodayStart(nowMs: number): number {
  const offsetSeconds = OFFICE_UTC_OFFSET_MINUTES * SECONDS_PER_MINUTE
  const localSeconds = Math.floor(nowMs / MS_PER_SECOND) + offsetSeconds
  return Math.floor(localSeconds / DAY_SECONDS) * DAY_SECONDS - offsetSeconds
}

/** The label under a bar: the short weekday for a week, the day of the month for a longer span. */
export function dayLabel(dayStart: number, count: number): string {
  const local = new Date((dayStart + OFFICE_UTC_OFFSET_MINUTES * SECONDS_PER_MINUTE) * MS_PER_SECOND)
  return count <= WEEKDAYS.length ? (WEEKDAYS[local.getUTCDay()] ?? '') : String(local.getUTCDate())
}

/** The biggest byte count of any day, download or upload. Zero when there is no traffic. */
function biggestDay(days: UsageDay[]): number {
  return Math.max(0, ...days.map((day) => Math.max(day.inBytes, day.outBytes)))
}

/** The bars of every day, scaled so the biggest value reaches the top of the plot. Days are spread evenly across the width. */
export function dayBars(days: UsageDay[]): DayBar[] {
  const plotHeight = CHART_HEIGHT - LABEL_ROOM
  const top = biggestDay(days)
  const slot = days.length === 0 ? 0 : CHART_WIDTH / days.length
  const width = (slot * PAIR_SHARE) / 2
  const heightOf = (bytes: number) => (top === 0 ? 0 : (bytes / top) * plotHeight)
  return days.map((day, index) => {
    const x = index * slot + (slot - width * 2) / 2
    return { day, x, width, inHeight: heightOf(day.inBytes), outHeight: heightOf(day.outBytes), outX: x + width }
  })
}
