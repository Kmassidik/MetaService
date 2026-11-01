// The chart of failed logins for the short ranges (1 h to 24 h): one small chart for each watched machine, a bar for every ten minutes, all on one scale (the tallest bucket
// of any machine), every bar starting at zero. A bucket the parent has no count for has no bar; it is never drawn as zero. The time axis is in the viewer's chosen zone.
// Pure functions: the zone and the clock are passed in.
import { MS_PER_MINUTE, RANGE_MS, TICK_MINUTES } from './securityRanges.ts'
import { clockLabel, minuteOfDay } from './securityTime.ts'
import type { BucketFailed, SecurityRange } from './securityTypes.ts'
import { isMacOs, type MachineInfo } from './securityView.ts'

export interface BucketTick {
  /** The bar the label sits under. */
  index: number
  /** "15:40", in the zone the chart was made for. */
  label: string
}

export interface BucketSeries {
  id: string
  name: string
  /** True for a Mac: its buckets count SSH connections, not failed logins. */
  connections: boolean
  /** Failed logins in each bucket, the oldest first and the current one last; null for a bucket with no count. */
  counts: (number | null)[]
  total: number
}

export interface BucketChartData {
  /** The first moment of each bucket, as milliseconds, oldest first. */
  starts: number[]
  minutes: number
  series: BucketSeries[]
  ticks: BucketTick[]
  /** The tallest bucket of any machine: the top of every chart. */
  tallest: number
}

/** The buckets a chart for this range holds, ending with the one `now` falls in. */
export function bucketStarts(range: SecurityRange, now: number, minutes: number): number[] {
  const length = minutes * MS_PER_MINUTE
  const count = Math.floor(RANGE_MS[range] / length)
  const last = Math.floor(now / length) * length
  return Array.from({ length: count }, (_, index) => last - (count - 1 - index) * length)
}

/** Labels on whole steps of the viewer's clock (every 10 minutes, hour, 2 or 3 hours, by range). */
export function bucketTicks(starts: number[], range: SecurityRange, zone: string): BucketTick[] {
  const step = TICK_MINUTES[range]
  if (step === 0) return []
  return starts.flatMap((start, index) => (minuteOfDay(start, zone) % step === 0 ? [{ index, label: clockLabel(start, zone) }] : []))
}

/** The series of the watched machines that have at least one counted bucket in the range. */
export function bucketChart(buckets: BucketFailed[], watched: MachineInfo[], range: SecurityRange, now: number, zone: string, minutes: number): BucketChartData {
  const starts = bucketStarts(range, now, minutes)
  const first = starts[0] ?? 0
  const length = minutes * MS_PER_MINUTE
  const counts = new Map<string, (number | null)[]>()
  for (const bucket of buckets) {
    const slot = Math.floor((Date.parse(bucket.start) - first) / length)
    if (bucket.failed === null || slot < 0 || slot >= starts.length) continue
    const own = counts.get(bucket.machine) ?? starts.map(() => null)
    own[slot] = (own[slot] ?? 0) + bucket.failed
    counts.set(bucket.machine, own)
  }
  const series = watched.flatMap((info) => {
    const own = counts.get(info.id)
    return own === undefined ? [] : [{ id: info.id, name: info.name, connections: isMacOs(info.os), counts: own, total: own.reduce<number>((sum, one) => sum + (one ?? 0), 0) }]
  })
  const tallest = Math.max(0, ...series.flatMap((one) => one.counts.map((count) => count ?? 0)))
  return { starts, minutes, series, ticks: bucketTicks(starts, range, zone), tallest }
}
