// The points the Live charts draw: the parent's last hour of readings first, then a point from the page's own polling each time one is due. Pure functions, no DOM.
import type { MachineStats, MachineStatsReply, StatsBreakdown, StatsHistoryPoint, StatsHistoryReply } from './types.ts'

/** One hour at one point every ten seconds. */
export const CHART_POINT_LIMIT = 360
export const DEFAULT_INTERVAL_SECONDS = 10
/** A reading that comes this much early still counts as the next point (the page asks every 5 seconds, the points are 10 apart). */
const EARLY_ALLOWANCE_SECONDS = 1
const MS_PER_SECOND = 1000

export interface LivePoint {
  /** Seconds since 1970. */
  t: number
  cpu: number
  breakdown: StatsBreakdown | null
  load: readonly [number, number, number] | null
  memUsed: number
  memCached: number
  memTotal: number
  swapUsed: number
  swapTotal: number
  diskRead: number | null
  diskWrite: number | null
  netIn: number | null
  netOut: number | null
  /** Packets dropped since boot (a running total; the page shows the change). */
  drops: number | null
  processes: number | null
}

export function pointFromHistory(point: StatsHistoryPoint): LivePoint {
  return {
    t: point.t, cpu: point.cpu_percent, breakdown: point.cpu_breakdown ?? null, load: point.load ?? null,
    memUsed: point.mem_used, memCached: point.mem_cached, memTotal: point.mem_total, swapUsed: point.swap_used, swapTotal: point.swap_total,
    diskRead: point.disk_read ?? null, diskWrite: point.disk_write ?? null, netIn: point.net_in_bps, netOut: point.net_out_bps,
    drops: point.net_drops ?? null, processes: point.processes_count ?? null,
  }
}

/** The history as points, oldest first, at most one hour. */
export function pointsFromHistory(reply: StatsHistoryReply): LivePoint[] {
  return reply.points.map(pointFromHistory).slice(-CHART_POINT_LIMIT)
}

function dropsOf(stats: MachineStats): number | null {
  const { drops_in_total: dropsIn, drops_out_total: dropsOut } = stats.network
  return dropsIn === undefined && dropsOut === undefined ? null : (dropsIn ?? 0) + (dropsOut ?? 0)
}

/** The seconds of a time text, or the fallback when it is not a time. */
function secondsOf(text: string | null, fallback: number): number {
  const parsed = text === null ? Number.NaN : Date.parse(text)
  return Number.isNaN(parsed) ? fallback : Math.floor(parsed / MS_PER_SECOND)
}

/** A point for a live reading; none while the machine is still measuring (a gap is truer than a 0). The time is when the parent got the reading. */
export function pointFromReading(reply: MachineStatsReply, nowSeconds: number): LivePoint | null {
  const stats = reply.stats
  if (reply.state !== 'online' || stats === null || stats.cpu.total_percent === null) return null
  return {
    t: secondsOf(reply.fetched_at, nowSeconds), cpu: stats.cpu.total_percent, breakdown: stats.cpu.breakdown ?? null,
    load: stats.cpu.load.one === null || stats.cpu.load.five === null || stats.cpu.load.fifteen === null ? null : [stats.cpu.load.one, stats.cpu.load.five, stats.cpu.load.fifteen],
    memUsed: stats.memory.used_bytes, memCached: stats.memory.cached_bytes, memTotal: stats.memory.total_bytes, swapUsed: stats.memory.swap_used_bytes, swapTotal: stats.memory.swap_total_bytes,
    diskRead: stats.disk_io?.read_bytes_per_second ?? null, diskWrite: stats.disk_io?.write_bytes_per_second ?? null,
    netIn: stats.network.received_bytes_per_second, netOut: stats.network.sent_bytes_per_second, drops: dropsOf(stats), processes: stats.process_count ?? null,
  }
}

/** The points with one more at the end, when it is newer by about one interval. Older, repeated or too-close readings are not added. At most one hour is kept. */
export function appendPoint(points: readonly LivePoint[], point: LivePoint, intervalSeconds: number = DEFAULT_INTERVAL_SECONDS): LivePoint[] {
  const last = points[points.length - 1]
  const due = last === undefined || point.t - last.t >= intervalSeconds - EARLY_ALLOWANCE_SECONDS
  return due ? [...points, point].slice(-CHART_POINT_LIMIT) : [...points]
}

/** The hour from the parent, then the live points that came in meanwhile and are newer than it. */
export function mergeHistory(history: readonly LivePoint[], live: readonly LivePoint[]): LivePoint[] {
  const newest = history[history.length - 1]?.t ?? Number.NEGATIVE_INFINITY
  return [...history, ...live.filter((point) => point.t > newest)].slice(-CHART_POINT_LIMIT)
}

/** A column of numbers out of the points, gaps kept as null. */
export const column = (points: readonly LivePoint[], pick: (point: LivePoint) => number | null): (number | null)[] => points.map(pick)

export interface Summary { latest: number | null; min: number | null; max: number | null; mean: number | null }

/** The newest, smallest, biggest and average value of a column; all null when there is nothing. */
export function summarize(values: readonly (number | null)[]): Summary {
  const present = values.filter((value): value is number => value !== null)
  if (present.length === 0) return { latest: null, min: null, max: null, mean: null }
  const latest = [...values].reverse().find((value): value is number => value !== null) ?? null
  return { latest, min: Math.min(...present), max: Math.max(...present), mean: present.reduce((sum, value) => sum + value, 0) / present.length }
}

/** How many packets were dropped between the first and the last reading of the points; null when the helper gives no drops or the counter went back (a restart). */
export function dropsInWindow(points: readonly LivePoint[]): number | null {
  const counted = points.map((point) => point.drops).filter((value): value is number => value !== null)
  const first = counted[0]
  const last = counted[counted.length - 1]
  return first === undefined || last === undefined || last < first ? null : last - first
}
