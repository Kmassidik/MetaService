// SAMPLE DATA ONLY. Answers the Security page from the made-up store of securityMock.ts, in the same shapes the parent will use, so the page cannot tell the
// difference. Only securitySource.ts loads this, and only when the address asks for the preview.
import { matchesQuery, pageOfEvents, rangeStart } from './securityFilter.ts'
import { MOCK_BUCKET_MINUTES, bucketEvents } from './securityMockBuckets.ts'
import { isShortRange } from './securityRanges.ts'
import { buildMockStore, type MockMachine, type MockStore } from './securityMock.ts'
import type { SecuritySource } from './securityApi.ts'
import type { BucketFailed, DailyFailed, EventQuery, SecurityEvent, SecurityMachineLine, SecurityOverview, SecurityRange, TopRow } from './securityTypes.ts'

const MINUTES_AGO_REPORTED = 4
const MINUTE_MS = 60_000
const DAY_MS = 86_400_000
const TOP_ROWS_KEPT = 50
const DAY_LENGTH = 10

/** A query that only has a time range: every machine, every type, no search. The page fields do not matter to matchesQuery. */
const everyEvent = (range: SecurityRange): EventQuery => ({ range, machine: '', type: '', q: '', page: 1, page_size: 1 })

/** The log of a range: the short ranges read the ten-minute counts, the long ones the daily rows. */
export const eventsFor = (store: MockStore, range: SecurityRange): SecurityEvent[] =>
  isShortRange(range) ? [...store.events.filter((event) => event.type !== 'failed_login'), ...bucketEvents(store.buckets)] : store.events

const failedIn = (store: MockStore, range: SecurityRange, now: number): SecurityEvent[] =>
  eventsFor(store, range).filter((event) => event.type === 'failed_login' && matchesQuery(event, everyEvent(range), now))

const sumOf = (events: SecurityEvent[]): number => events.reduce((sum, event) => sum + (event.count ?? 0), 0)

function machineLine(machine: MockMachine, store: MockStore, range: SecurityRange, now: number): SecurityMachineLine {
  const own = failedIn(store, range, now).filter((event) => event.machine === machine.id)
  const blocks = eventsFor(store, range).filter((event) => event.machine === machine.id && event.type === 'blocked' && matchesQuery(event, everyEvent(range), now))
  return { machine: machine.id, reported: true, last_reported: new Date(now - MINUTES_AGO_REPORTED * MINUTE_MS).toISOString(), baseline: machine.baseline, failed: sumOf(own), blocked: blocks.length }
}

function topBy(events: SecurityEvent[], field: 'user' | 'address'): TopRow[] {
  const totals = new Map<string, number>()
  for (const event of events) {
    const name = event[field]
    if (name !== null) totals.set(name, (totals.get(name) ?? 0) + (event.count ?? 0))
  }
  return [...totals].map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count).slice(0, TOP_ROWS_KEPT)
}

function dailyOf(events: SecurityEvent[]): DailyFailed[] {
  const totals = new Map<string, DailyFailed>()
  for (const event of events) {
    const day = event.time.slice(0, DAY_LENGTH)
    const id = `${event.machine}/${day}`
    totals.set(id, { day, machine: event.machine, failed: (totals.get(id)?.failed ?? 0) + (event.count ?? 0) })
  }
  return [...totals.values()]
}

function bucketsOf(events: SecurityEvent[]): BucketFailed[] {
  const totals = new Map<string, BucketFailed>()
  for (const event of events) {
    const id = `${event.machine}/${event.time}`
    totals.set(id, { start: event.time, machine: event.machine, failed: (totals.get(id)?.failed ?? 0) + (event.count ?? 0) })
  }
  return [...totals.values()].sort((a, b) => a.start.localeCompare(b.start))
}

export function mockOverview(store: MockStore, range: SecurityRange, now: number): SecurityOverview {
  const failed = failedIn(store, range, now)
  return {
    range, generated_at: new Date(now).toISOString(),
    machines: store.machines.filter((machine) => machine.reports).map((machine) => machineLine(machine, store, range, now)),
    blocked_now: store.blocked_now, top_users: topBy(failed, 'user'), top_addresses: topBy(failed, 'address'),
    // The chart shows whole days, so a day is counted whole whatever the range cuts through.
    daily: isShortRange(range) ? [] : dailyOf(store.events.filter((event) => event.type === 'failed_login' && Date.parse(event.time) >= rangeStart(range, now) - DAY_MS)),
    buckets: isShortRange(range) ? bucketsOf(failed) : [], bucket_minutes: MOCK_BUCKET_MINUTES,
  }
}

/** The sample as of `now`: a source that answers from it, and the four machines the table lists. */
export function mockPreview(now: number): { source: SecuritySource; machines: MockMachine[] } {
  const store = buildMockStore(now)
  const source: SecuritySource = {
    overview: async (range) => mockOverview(store, range, now),
    events: async (query: EventQuery) => pageOfEvents(eventsFor(store, query.range), query, now),
  }
  return { source, machines: store.machines }
}
