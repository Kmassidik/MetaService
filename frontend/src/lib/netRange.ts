// The range switch of the Network tab: which ranges there are, how long each one is, how often the tab asks for it, and which range the latency route
// answers for it (the 30 day view uses the 7 day probes). Pure functions, no DOM.
import type { LatencyRange } from './latencyParse.ts'

export const NET_RANGES = ['1h', '24h', '7d', '30d'] as const
export type NetRange = (typeof NET_RANGES)[number]
export const DEFAULT_NET_RANGE: NetRange = '1h'

const HOUR_SECONDS = 3600
const DAY_SECONDS = 86_400
/** The hour is asked for every 10 seconds, like the Live tab; the longer ranges every minute. */
const HOUR_POLL_MS = 10_000
const LONGER_POLL_MS = 60_000

interface RangeInfo {
  label: string
  windowSeconds: number
  windowName: string
}

const INFO: Record<NetRange, RangeInfo> = {
  '1h': { label: '1 hour', windowSeconds: HOUR_SECONDS, windowName: 'last hour' },
  '24h': { label: '24 hours', windowSeconds: DAY_SECONDS, windowName: 'last 24 hours' },
  '7d': { label: '7 days', windowSeconds: 7 * DAY_SECONDS, windowName: 'last 7 days' },
  '30d': { label: '30 days', windowSeconds: 30 * DAY_SECONDS, windowName: 'last 30 days' },
}

/** The words and the length of a range: the switch's label, the seconds the chart spans and the caption's name for it. */
export function windowOf(range: NetRange): RangeInfo {
  return INFO[range]
}

/** How often the tab asks for a range: every 10 seconds for the hour, every minute for the others. */
export function pollMsOf(range: NetRange): number {
  return range === '1h' ? HOUR_POLL_MS : LONGER_POLL_MS
}

/** The range the latency route is asked for: it answers 1 hour, 24 hours and 7 days, so 30 days shows the 7 days. */
export function latencyRangeOf(range: NetRange): LatencyRange {
  return range === '30d' ? '7d' : range
}

/** A small note under the latency chart when it shows less than the range; empty when it shows the whole range. */
export function latencyNoteOf(range: NetRange): string {
  return range === '30d' ? 'Latency shows the last 7 days.' : ''
}
