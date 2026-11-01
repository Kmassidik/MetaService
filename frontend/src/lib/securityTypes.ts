// The data shapes of the Security page: what GET /api/security/overview and GET /api/security/events give once the panel has read them.
// Every count is a number or null: null means "the parent did not say", never zero. All text is plain text, already length-capped by securityParse.ts.
import type { SecurityBaseline } from './types.ts'

export const RANGES = ['1h', '6h', '12h', '24h', '7d', '30d', '90d'] as const
export type SecurityRange = (typeof RANGES)[number]
export const DEFAULT_RANGE: SecurityRange = '7d'
export const RANGE_LABELS: Record<SecurityRange, string> = { '1h': '1 h', '6h': '6 h', '12h': '12 h', '24h': '24 h', '7d': '7 d', '30d': '30 d', '90d': '90 d' }
/** How many days back each range reaches (the short ranges are fractions of a day). */
export const RANGE_DAYS: Record<SecurityRange, number> = { '1h': 1 / 24, '6h': 0.25, '12h': 0.5, '24h': 1, '7d': 7, '30d': 30, '90d': 90 }

export const EVENT_TYPES = ['failed_login', 'blocked', 'unblocked', 'login'] as const
export type SecurityEventType = (typeof EVENT_TYPES)[number]
export const EVENT_TYPE_LABELS: Record<SecurityEventType, string> = {
  failed_login: 'Failed login', blocked: 'Address blocked', unblocked: 'Address unblocked', login: 'Successful login',
}

/** One machine's line in the overview. `reported` false (or no line at all) means nobody is watching it yet. */
export interface SecurityMachineLine {
  machine: string
  reported: boolean
  last_reported: string | null
  baseline: SecurityBaseline
  failed: number | null
  blocked: number | null
}

export interface BlockedNowRow {
  machine: string
  address: string
  since: string | null
  until: string | null
  attempts: number | null
}

/** A user name or an address with how often it was tried. */
export interface TopRow {
  name: string
  count: number
}

/** Failed logins on one day (UTC, YYYY-MM-DD) on one machine. */
export interface DailyFailed {
  day: string
  machine: string
  failed: number | null
}

/** Failed logins in one ten-minute UTC bucket (`start` is the bucket's first moment) on one machine. A bucket without a count has no row. */
export interface BucketFailed {
  start: string
  machine: string
  failed: number | null
}

export interface SecurityOverview {
  range: SecurityRange
  generated_at: string | null
  machines: SecurityMachineLine[]
  blocked_now: BlockedNowRow[]
  top_users: TopRow[]
  top_addresses: TopRow[]
  daily: DailyFailed[]
  /** Ten-minute counts for the ranges up to 24 hours; empty for longer ranges and from a parent that does not send them. */
  buckets: BucketFailed[]
  /** How long one bucket is; null when the parent did not say. */
  bucket_minutes: number | null
}

export interface SecurityEvent {
  id: string
  time: string
  machine: string
  type: SecurityEventType
  user: string | null
  address: string | null
  detail: string | null
  /** For a successful login: how it got in. A password login is highlighted. */
  method: 'key' | 'password' | null
  /** For a failed login: how many tries this row stands for (failed logins are stored as daily counts). */
  count: number | null
}

/** One page of the log, as the parent counts it: `total` is every row that matches the filters, `page` starts at 1. */
export interface EventsPage {
  events: SecurityEvent[]
  total: number
  page: number
  page_size: number
}

/** What the person asked the log to show. Empty text means "any". */
export interface EventQuery {
  range: SecurityRange
  machine: string
  type: SecurityEventType | ''
  q: string
  /** The page wanted, starting at 1, and how many rows it holds. */
  page: number
  page_size: number
}

/** The most rows one page of the log may hold; the parent caps `page_size` here and the panel reads no more than this from one answer. */
export const MAX_EVENTS_PAGE_SIZE = 100
