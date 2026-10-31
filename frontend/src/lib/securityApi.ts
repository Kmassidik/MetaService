// The two calls of the Security page to the parent: GET /api/security/overview and GET /api/security/events. Each answer is read by securityParse.ts.
// A 404 means the parent has no security API yet; that is not an error, it gives null and the page says so. Any other refusal is thrown.
import { ApiError, getUnchecked } from './api.ts'
import { parseEvents, parseOverview } from './securityParse.ts'
import type { EventQuery, EventsPage, SecurityOverview, SecurityRange } from './securityTypes.ts'

export const OVERVIEW_PATH = '/api/security/overview'
export const EVENTS_PATH = '/api/security/events'
const NOT_FOUND = 404

/** A page-by-page source of security data: the real parent, or the sample data. Null means "no security API here". */
export interface SecuritySource {
  overview: (range: SecurityRange) => Promise<SecurityOverview | null>
  events: (query: EventQuery) => Promise<EventsPage | null>
}

/** The address of the overview for a range. */
export const overviewPath = (range: SecurityRange): string => `${OVERVIEW_PATH}?${new URLSearchParams({ range })}`

/** The address of one page of the log. An empty filter is left out; the cursor is only sent for the second page and later. */
export function eventsPath(query: EventQuery): string {
  const params = new URLSearchParams({ range: query.range })
  if (query.machine !== '') params.set('machine', query.machine)
  if (query.type !== '') params.set('type', query.type)
  if (query.q.trim() !== '') params.set('q', query.q.trim())
  if (query.cursor !== null) params.set('cursor', query.cursor)
  return `${EVENTS_PATH}?${params}`
}

/** Runs a call; a 404 answer is "not there" (null), every other failure is passed on. */
async function orMissing<T>(work: () => Promise<T>): Promise<T | null> {
  try {
    return await work()
  } catch (error) {
    if (error instanceof ApiError && error.status === NOT_FOUND) return null
    throw error
  }
}

export const getSecurityOverview = (range: SecurityRange): Promise<SecurityOverview | null> => orMissing(async () => parseOverview(await getUnchecked(overviewPath(range))))

export const getSecurityEvents = (query: EventQuery): Promise<EventsPage | null> => orMissing(async () => parseEvents(await getUnchecked(eventsPath(query))))

/** The real parent. It never touches the sample data. */
export const realSource: SecuritySource = { overview: getSecurityOverview, events: getSecurityEvents }
