// Reads the answer of GET /api/machines/{id}/network/series (24 hours, 7 days or 30 days) and turns the stats history into the same shape.
// Nothing here trusts the shape: a field of the wrong type becomes a safe default, a negative or NaN speed is a gap (null), never a zero,
// and the points are capped at the newest MAX_NET_POINTS. The parser never throws. Pure: no DOM.

export const NET_SERIES_RANGES = ['24h', '7d', '30d'] as const
export type NetSeriesRange = (typeof NET_SERIES_RANGES)[number]

/** The most points kept from one answer. When there are more, the newest are kept. */
export const MAX_NET_POINTS = 1000
/** The longest range text kept; anything longer is cut. */
const MAX_TEXT = 100
/** A gap of more than this many buckets between two points is drawn as a break in the line. */
const GAP_FACTOR = 1.5

/** One bucket of speed. In and out are bytes per second; a null is a gap (no reading in that bucket). */
export interface NetSeriesPoint {
  t: number
  inBps: number | null
  outBps: number | null
  inPeakBps: number | null
  outPeakBps: number | null
}

export interface NetSeries {
  range: string
  bucketSeconds: number
  points: NetSeriesPoint[]
}

/** The two speeds of one stats history point, as the Live tab reads them. */
export interface HistoryRate {
  t: number
  netIn: number | null
  netOut: number | null
}

type Fields = Record<string, unknown>

const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)
const isPoint = (point: NetSeriesPoint | null): point is NetSeriesPoint => point !== null

/** A finite speed from zero up, or null: a missing, negative or non-numeric speed is a gap. */
function rateOf(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}

/** A finite time in seconds, or null when it is not a time. */
function timeOf(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/** A finite bucket length above zero, or 0 for "unknown". */
function bucketOf(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0
}

/** The text with its control characters removed (\p{Cc}) and cut short; anything that is not text is empty. */
function textOf(value: unknown): string {
  if (typeof value !== 'string') return ''
  return value.replace(/\p{Cc}/gu, '').slice(0, MAX_TEXT)
}

/** One point of the network series, or null when it has no usable time. */
function pointOf(raw: unknown): NetSeriesPoint | null {
  if (!isFields(raw)) return null
  const t = timeOf(raw.t)
  if (t === null) return null
  return { t, inBps: rateOf(raw.in_bps), outBps: rateOf(raw.out_bps), inPeakBps: rateOf(raw.in_peak_bps), outPeakBps: rateOf(raw.out_peak_bps) }
}

/** The network series answer, every field checked. Points without a usable time are left out; the newest MAX_NET_POINTS are kept. */
export function parseNetSeries(raw: unknown): NetSeries {
  const source = isFields(raw) ? raw : {}
  const rows: unknown[] = Array.isArray(source.points) ? source.points : []
  return {
    range: textOf(source.range),
    bucketSeconds: bucketOf(source.bucket_seconds),
    points: rows.map(pointOf).filter(isPoint).slice(-MAX_NET_POINTS),
  }
}

/** A point with no readings at all, placed at a time. */
function emptyAt(t: number): NetSeriesPoint {
  return { t, inBps: null, outBps: null, inPeakBps: null, outPeakBps: null }
}

/** One stats history point as a series point (the history has no peaks); null when it has no usable time. */
function historyPointOf(point: HistoryRate): NetSeriesPoint | null {
  const t = timeOf(point.t)
  if (t === null) return null
  return { t, inBps: rateOf(point.netIn), outBps: rateOf(point.netOut), inPeakBps: null, outPeakBps: null }
}

/** The stats history (the last hour, every 10 seconds) in the same shape as the network series. */
export function seriesFromHistory(points: readonly HistoryRate[]): NetSeriesPoint[] {
  return points.map(historyPointOf).filter(isPoint).slice(-MAX_NET_POINTS)
}

/** Puts an empty point between two points more than 1.5 buckets apart, so the line breaks there instead of bridging the missing buckets. A zero bucket length adds nothing. */
export function withGaps(points: readonly NetSeriesPoint[], bucketSeconds: number): NetSeriesPoint[] {
  if (bucketSeconds <= 0) return [...points]
  return points.flatMap((point, index) => {
    const previous = points[index - 1]
    const apart = previous === undefined || point.t - previous.t <= bucketSeconds * GAP_FACTOR
    return apart ? [point] : [emptyAt(previous.t + bucketSeconds), point]
  })
}
