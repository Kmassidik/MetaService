// The data shapes of the Security page: what GET /api/security/overview and GET /api/security/events give once the panel has read them.
// Every count is a number or null: null means "the parent did not say", never zero. All text is plain text, already length-capped by securityParse.ts.
import type { SecurityBaseline } from './types.ts'

export const RANGES = ['24h', '7d', '30d', '90d'] as const
export type SecurityRange = (typeof RANGES)[number]
export const DEFAULT_RANGE: SecurityRange = '7d'
export const RANGE_LABELS: Record<SecurityRange, string> = { '24h': '24 h', '7d': '7 d', '30d': '30 d', '90d': '90 d' }
export const RANGE_DAYS: Record<SecurityRange, number> = { '24h': 1, '7d': 7, '30d': 30, '90d': 90 }

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

export interface SecurityOverview {
  range: SecurityRange
  generated_at: string | null
  machines: SecurityMachineLine[]
  blocked_now: BlockedNowRow[]
  top_users: TopRow[]
  top_addresses: TopRow[]
  daily: DailyFailed[]
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

export interface EventsPage {
  events: SecurityEvent[]
  /** Hand this back as `cursor` for the next page; null when there are no more. */
  next_cursor: string | null
}

/** What the person asked the log to show. Empty text means "any". */
export interface EventQuery {
  range: SecurityRange
  machine: string
  type: SecurityEventType | ''
  q: string
  cursor: string | null
}

/** Rows asked for on each page of the log. */
export const EVENTS_PAGE_SIZE = 50
/** The log never holds more rows than this in the page; the person is told to narrow the filters. */
export const MAX_LOADED_EVENTS = 1000
