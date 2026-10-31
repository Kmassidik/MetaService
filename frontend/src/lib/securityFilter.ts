// How a list of events is narrowed and paged: by time range, machine, type and a text search on the address or user; newest first; one page of up to 100 rows. The real parent does this on the server; the sample data (securityMock.ts) uses these same functions, and the tests pin the rules. Pure functions.
import { pageBounds } from './paging.ts'
import { MAX_EVENTS_PAGE_SIZE, RANGE_DAYS, type EventQuery, type EventsPage, type SecurityEvent, type SecurityRange } from './securityTypes.ts'

const DAY_MS = 86_400_000

/** The start of a range: that many days before `now`. */
export const rangeStart = (range: SecurityRange, now: number): number => now - RANGE_DAYS[range] * DAY_MS

const eventTime = (event: SecurityEvent): number => Date.parse(event.time)

/** True when the event's address or user contains the search text, ignoring letter case. An empty search matches everything. */
export function matchesText(event: SecurityEvent, text: string): boolean {
  const wanted = text.trim().toLowerCase()
  if (wanted === '') return true
  return [event.address, event.user].some((field) => field !== null && field.toLowerCase().includes(wanted))
}

/** True when the event passes the range, machine, type and text of the query. */
export function matchesQuery(event: SecurityEvent, query: EventQuery, now: number): boolean {
  if (eventTime(event) < rangeStart(query.range, now) || eventTime(event) > now) return false
  if (query.machine !== '' && event.machine !== query.machine) return false
  if (query.type !== '' && event.type !== query.type) return false
  return matchesText(event, query.q)
}

/** Newest first; equal times keep their order. */
export const newestFirst = (events: SecurityEvent[]): SecurityEvent[] => [...events].sort((a, b) => eventTime(b) - eventTime(a))

/** One page of the matching events, newest first (offset paging; the page size is capped like the parent caps it). */
export function pageOfEvents(events: SecurityEvent[], query: EventQuery, now: number): EventsPage {
  const matching = newestFirst(events.filter((event) => matchesQuery(event, query, now)))
  const pageSize = Math.min(Math.max(query.page_size, 1), MAX_EVENTS_PAGE_SIZE)
  const { page, start, end } = pageBounds(query.page, matching.length, pageSize)
  return { events: matching.slice(start, end), total: matching.length, page, page_size: pageSize }
}
