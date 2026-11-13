// Reads the answer of GET /api/machines/{id}/latency. Nothing here trusts the shape: a field of the wrong type becomes a safe default (0 or null),
// never a made-up number; a negative or non-finite time is unknown (null); the points are capped. The parser never throws, so a bad answer shows as
// "No readings yet" and does not break the page.

export const RANGES = ['1h', '24h', '7d'] as const
export type LatencyRange = (typeof RANGES)[number]
export type LatencyState = 'ok' | 'slow' | 'down' | 'none'

/** A last reading above this many milliseconds makes the machine Slow. */
export const SLOW_MS = 100
/** A share of lost probes (in percent) above this makes the machine Slow. */
export const LOSS_PERCENT = 5
/** The most points kept from one answer, so a huge answer cannot make the page heavy. */
export const MAX_POINTS = 1000
const PERCENT_MAX = 100

export interface LatencySummary {
  count: number
  failed: number
  averageMs: number | null
  maxMs: number | null
  lastMs: number | null
  percentFailed: number
}

/** One probe. `ms` is null when the probe failed at that time. */
export interface LatencyPoint {
  t: number
  ms: number | null
}

export interface Latency {
  range: string
  intervalSeconds: number
  summary: LatencySummary
  points: LatencyPoint[]
}

type Fields = Record<string, unknown>

const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)
const isPoint = (point: LatencyPoint | null): point is LatencyPoint => point !== null

/** A whole number from zero up, or 0 when the value is anything else. */
function count(value: unknown): number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : 0
}

/** A finite number from zero up, or null when it is missing, negative or not a number. */
function millis(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}

/** A finite number above zero, or 0 for "unknown". */
function interval(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0
}

/** The reported loss, kept between 0 and 100. When it is missing, it is worked out from the counts. */
function percentOf(value: unknown, failed: number, total: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.min(Math.max(value, 0), PERCENT_MAX)
  return total === 0 ? 0 : (failed / total) * PERCENT_MAX
}

/** The summary block with every number checked. A missing block is an empty summary. */
function summaryOf(raw: unknown): LatencySummary {
  const source = isFields(raw) ? raw : {}
  const total = count(source.count)
  const failed = Math.min(count(source.failed), total)
  return {
    count: total,
    failed,
    averageMs: millis(source.average_ms),
    maxMs: millis(source.max_ms),
    lastMs: millis(source.last_ms),
    percentFailed: percentOf(source.percent_failed, failed, total),
  }
}

/** One probe, or null when it has no usable time. */
function pointOf(raw: unknown): LatencyPoint | null {
  if (!isFields(raw)) return null
  const t = raw.t
  if (typeof t !== 'number' || !Number.isFinite(t)) return null
  return { t, ms: millis(raw.ms) }
}

/** The latency answer for one machine, every field checked. Points without a usable time are left out. */
export function parseLatency(raw: unknown): Latency {
  const source = isFields(raw) ? raw : {}
  const rows = Array.isArray(source.points) ? source.points : []
  return {
    range: typeof source.range === 'string' ? source.range : '',
    intervalSeconds: interval(source.interval_seconds),
    summary: summaryOf(source.summary),
    points: rows.map(pointOf).filter(isPoint).slice(0, MAX_POINTS),
  }
}

/** How a machine's readings look: none (no probes yet), down (every probe failed), slow (last reading or loss too high), otherwise ok. */
export function latencyState(latency: Latency): LatencyState {
  const { count: total, failed, lastMs, percentFailed } = latency.summary
  if (total === 0) return 'none'
  if (failed === total) return 'down'
  const slow = (lastMs !== null && lastMs > SLOW_MS) || percentFailed > LOSS_PERCENT
  return slow ? 'slow' : 'ok'
}
