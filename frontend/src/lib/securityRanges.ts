// What the time ranges of the Security page mean: how long each one is, the words for it in a sentence, and whether it is drawn from ten-minute buckets (up to 24 hours)
// or from UTC days (longer). Pure data and functions.
import type { SecurityRange } from './securityTypes.ts'

const HOUR_MS = 3_600_000
const DAY_MS = 24 * HOUR_MS
/** The length of one bucket the parent counts in, when it does not say. */
export const DEFAULT_BUCKET_MINUTES = 10
export const MS_PER_MINUTE = 60_000

export const RANGE_MS: Record<SecurityRange, number> = {
  '1h': HOUR_MS, '6h': 6 * HOUR_MS, '12h': 12 * HOUR_MS, '24h': DAY_MS, '7d': 7 * DAY_MS, '30d': 30 * DAY_MS, '90d': 90 * DAY_MS,
}

/** "in the last 6 hours": the range as it reads in a sentence. */
export const RANGE_PHRASE: Record<SecurityRange, string> = {
  '1h': 'in the last hour', '6h': 'in the last 6 hours', '12h': 'in the last 12 hours', '24h': 'in the last 24 hours',
  '7d': 'in the last 7 days', '30d': 'in the last 30 days', '90d': 'in the last 90 days',
}

/** True for the ranges drawn from ten-minute buckets. */
export const isShortRange = (range: SecurityRange): boolean => RANGE_MS[range] <= DAY_MS

/** Minutes between two labels on the time axis: 1 h every 10 minutes, 6 h every hour, 12 h every 2 hours, 24 h every 3 hours. */
export const TICK_MINUTES: Record<SecurityRange, number> = { '1h': 10, '6h': 60, '12h': 120, '24h': 180, '7d': 0, '30d': 0, '90d': 0 }

/** The bucket length to draw with: the parent's, or ten minutes when it did not say or said something that makes no sense. */
export function bucketMinutesOf(told: number | null): number {
  const sensible = told !== null && told >= 1 && told <= 60 && 60 % told === 0
  return sensible ? told : DEFAULT_BUCKET_MINUTES
}
