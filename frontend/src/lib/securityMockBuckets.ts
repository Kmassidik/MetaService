// SAMPLE DATA ONLY (see securityMock.ts). The ten-minute failed-login counts of the last 24 hours that the short ranges (1 h to 24 h) of the preview are drawn from.
import { MS_PER_MINUTE, RANGE_MS } from './securityRanges.ts'
import type { SecurityEvent } from './securityTypes.ts'

export const MOCK_BUCKET_MINUTES = 10
const BUCKET_MS = MOCK_BUCKET_MINUTES * MS_PER_MINUTE
const BUCKETS_KEPT = RANGE_MS['24h'] / BUCKET_MS
/** About this share of the buckets have a count; the rest had none, and have no row. */
const BUSY_SHARE = 0.7
const BURST_EVERY = 37

/** One machine's failed logins (or a Mac's SSH connections: no user, no address) in one bucket. */
export interface MockBucket {
  start: string
  machine: string
  user: string | null
  address: string | null
  count: number
}

/** A source of numbers in [0, 1) and the attackers a machine is attacked by. */
export interface BucketAttackers {
  machine: string
  /** The average count of a busy bucket. */
  perBucket: number
  addresses: string[]
  /** Null for a Mac, which cannot say who connected. */
  user: ((next: () => number) => string) | null
}

export function bucketRows(attackers: BucketAttackers, now: number, next: () => number): MockBucket[] {
  const last = Math.floor(now / BUCKET_MS) * BUCKET_MS
  const rows: MockBucket[] = []
  for (let back = 0; back < BUCKETS_KEPT; back++) {
    if (next() > BUSY_SHARE) continue
    const burst = back % BURST_EVERY === 3 ? 4 : 1
    const address = attackers.addresses[Math.floor(next() * attackers.addresses.length)] ?? null
    const count = Math.max(1, Math.round(attackers.perBucket * (0.3 + next() * 1.4) * burst))
    rows.push({ start: new Date(last - back * BUCKET_MS).toISOString(), machine: attackers.machine, user: attackers.user === null ? null : attackers.user(next), address: attackers.user === null ? null : address, count })
  }
  return rows
}

const FAILED_DETAIL = 'Invalid user, password refused'

/** The same buckets as log rows, newest first by time, for the Event log of a short range. */
export function bucketEvents(buckets: MockBucket[]): SecurityEvent[] {
  return buckets.map((bucket, index) => ({
    id: `bucket-${bucket.machine}-${index}`, time: new Date(Date.parse(bucket.start)).toISOString(), machine: bucket.machine, type: 'failed_login' as const,
    user: bucket.user, address: bucket.address, detail: bucket.user === null ? null : FAILED_DETAIL, method: null, count: bucket.count,
  }))
}
