// Reads the two answers of the Security API the way the parent sent them, defensively (in the style of statsParse.ts): a value of the wrong type is dropped
// to "unknown" (null), never to zero; a row that cannot be read is left out; text is cleaned and cut short; every list is capped. A wrong top-level shape
// throws UnreadableAnswer so the page says it could not read the answer. Pure functions, no DOM, no network.
import { readBaseline } from './security.ts'
import { MAX_DETAIL, MAX_TEXT, clean, flag, isRec, rows, when, whole, type Rec } from './securityPrims.ts'
import {
  DEFAULT_RANGE, EVENT_TYPES, RANGES, type BlockedNowRow, type DailyFailed, type EventsPage, type SecurityEvent, type SecurityEventType, type SecurityMachineLine,
  type SecurityOverview, type SecurityRange, type TopRow,
} from './securityTypes.ts'
import { UnreadableAnswer } from './unreadable.ts'

/** Caps: the most rows of each list the panel keeps. */
export const MAX_MACHINES = 100
export const MAX_BLOCKED_NOW = 200
export const MAX_TOP_ROWS = 50
export const MAX_DAILY_POINTS = 5000
export const MAX_EVENTS_PER_PAGE = 200
const MAX_ID_TEXT = 64
const MAX_CURSOR_TEXT = 200
const DAY_FORMAT = /^\d{4}-\d{2}-\d{2}$/

const rangeOf = (value: unknown): SecurityRange => RANGES.find((range) => range === value) ?? DEFAULT_RANGE
const typeOf = (value: unknown): SecurityEventType | null => EVENT_TYPES.find((type) => type === value) ?? null

function machineLine(value: unknown): SecurityMachineLine | null {
  if (!isRec(value)) return null
  const machine = clean(value.machine, MAX_ID_TEXT)
  if (machine === null) return null
  const lastReported = when(value.last_reported)
  // A machine counts as watched only when the parent says so and gives a time; a bare number is never enough.
  return { machine, reported: flag(value.reported) === true && lastReported !== null, last_reported: lastReported, baseline: readBaseline(value.baseline), failed: whole(value.failed), blocked: whole(value.blocked) }
}

function blockedRow(value: unknown): BlockedNowRow | null {
  if (!isRec(value)) return null
  const machine = clean(value.machine, MAX_ID_TEXT)
  const address = clean(value.address, MAX_TEXT)
  if (machine === null || address === null) return null
  return { machine, address, since: when(value.since), until: when(value.until), attempts: whole(value.attempts) }
}

function topRow(value: unknown): TopRow | null {
  if (!isRec(value)) return null
  const name = clean(value.name, MAX_TEXT)
  const count = whole(value.count)
  return name === null || count === null ? null : { name, count }
}

function dailyPoint(value: unknown): DailyFailed | null {
  if (!isRec(value)) return null
  const machine = clean(value.machine, MAX_ID_TEXT)
  const day = clean(value.day, MAX_ID_TEXT)
  if (machine === null || day === null || !DAY_FORMAT.test(day)) return null
  return { day, machine, failed: whole(value.failed) }
}

function record(value: unknown, what: string): Rec {
  if (!isRec(value)) throw new UnreadableAnswer(`${what} is not an object`)
  return value
}

/** The answer of GET /api/security/overview. */
export function parseOverview(value: unknown): SecurityOverview {
  const body = record(value, 'the security overview')
  return {
    range: rangeOf(body.range),
    generated_at: when(body.generated_at),
    machines: rows(body.machines, machineLine, MAX_MACHINES),
    blocked_now: rows(body.blocked_now, blockedRow, MAX_BLOCKED_NOW),
    top_users: rows(body.top_users, topRow, MAX_TOP_ROWS),
    top_addresses: rows(body.top_addresses, topRow, MAX_TOP_ROWS),
    daily: rows(body.daily, dailyPoint, MAX_DAILY_POINTS),
  }
}

function methodOf(value: unknown): 'key' | 'password' | null {
  return value === 'key' || value === 'password' ? value : null
}

function eventRow(value: unknown): SecurityEvent | null {
  if (!isRec(value)) return null
  const id = clean(value.id, MAX_ID_TEXT)
  const time = when(value.time)
  const machine = clean(value.machine, MAX_ID_TEXT)
  const type = typeOf(value.type)
  if (id === null || time === null || machine === null || type === null) return null
  return { id, time, machine, type, user: clean(value.user, MAX_TEXT), address: clean(value.address, MAX_TEXT), detail: clean(value.detail, MAX_DETAIL), method: methodOf(value.method), count: whole(value.count) }
}

/** The answer of GET /api/security/events. */
export function parseEvents(value: unknown): EventsPage {
  const body = record(value, 'the security events')
  return { events: rows(body.events, eventRow, MAX_EVENTS_PER_PAGE), next_cursor: clean(body.next_cursor, MAX_CURSOR_TEXT) }
}
