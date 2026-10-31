import { expect, test } from 'bun:test'
import { matchesText, pageOfEvents, rangeStart } from './securityFilter.ts'
import { EVENTS_PAGE_SIZE, type EventQuery, type SecurityEvent } from './securityTypes.ts'

const NOW = Date.parse('2026-11-01T12:00:00Z')
const HOUR_MS = 3_600_000
const at = (hoursAgo: number): string => new Date(NOW - hoursAgo * HOUR_MS).toISOString()

function event(id: string, hoursAgo: number, extra: Partial<SecurityEvent> = {}): SecurityEvent {
  return { id, time: at(hoursAgo), machine: 'rtx-pc', type: 'failed_login', user: 'root', address: '203.0.113.9', detail: null, method: null, count: 3, ...extra }
}

const query = (extra: Partial<EventQuery> = {}): EventQuery => ({ range: '7d', machine: '', type: '', q: '', cursor: null, ...extra })
const ids = (events: SecurityEvent[]) => events.map((one) => one.id)

test('a range starts that many days before now', () => {
  expect(rangeStart('24h', NOW)).toBe(NOW - 24 * HOUR_MS)
  expect(rangeStart('90d', NOW)).toBe(NOW - 90 * 24 * HOUR_MS)
})

test('the range narrows the log', () => {
  const events = [event('new', 1), event('two-days', 48), event('ten-days', 240)]
  expect(ids(pageOfEvents(events, query({ range: '24h' }), NOW).events)).toEqual(['new'])
  expect(ids(pageOfEvents(events, query({ range: '7d' }), NOW).events)).toEqual(['new', 'two-days'])
  expect(ids(pageOfEvents(events, query({ range: '30d' }), NOW).events)).toEqual(['new', 'two-days', 'ten-days'])
})

test('the log is newest first, whatever order it came in', () => {
  expect(ids(pageOfEvents([event('b', 5), event('a', 1), event('c', 9)], query(), NOW).events)).toEqual(['a', 'b', 'c'])
})

test('machine and type each narrow the log', () => {
  const events = [event('a', 1), event('b', 2, { machine: 'dgx-spark' }), event('c', 3, { type: 'blocked' })]
  expect(ids(pageOfEvents(events, query({ machine: 'dgx-spark' }), NOW).events)).toEqual(['b'])
  expect(ids(pageOfEvents(events, query({ type: 'blocked' }), NOW).events)).toEqual(['c'])
  expect(ids(pageOfEvents(events, query({ machine: 'rtx-pc', type: 'blocked' }), NOW).events)).toEqual(['c'])
})

test('the text search looks at the address and the user, ignoring letter case, and nowhere else', () => {
  const one = event('a', 1, { user: 'Postgres', address: '45.148.10.92', detail: 'secret words' })
  expect(matchesText(one, 'postg')).toBe(true)
  expect(matchesText(one, '45.148')).toBe(true)
  expect(matchesText(one, 'secret')).toBe(false)
  expect(matchesText(one, '  ')).toBe(true)
  expect(matchesText(event('b', 1, { user: null, address: null }), 'x')).toBe(false)
})

test('events in the future are not shown', () => {
  expect(pageOfEvents([event('later', -2)], query(), NOW).events).toEqual([])
})

test('the log comes 50 rows a page, with a cursor to the next page and none on the last', () => {
  const events = Array.from({ length: EVENTS_PAGE_SIZE * 2 + 5 }, (_, index) => event(`e${index}`, index / 10))
  const first = pageOfEvents(events, query(), NOW)
  expect(first.events).toHaveLength(EVENTS_PAGE_SIZE)
  expect(first.next_cursor).not.toBeNull()
  const second = pageOfEvents(events, query({ cursor: first.next_cursor }), NOW)
  expect(second.events).toHaveLength(EVENTS_PAGE_SIZE)
  const third = pageOfEvents(events, query({ cursor: second.next_cursor }), NOW)
  expect(third.events).toHaveLength(5)
  expect(third.next_cursor).toBeNull()
  expect(new Set([...first.events, ...second.events, ...third.events].map((one) => one.id)).size).toBe(events.length)
})

test('a cursor that is not a number starts from the top', () => {
  const events = [event('a', 1)]
  expect(ids(pageOfEvents(events, query({ cursor: 'junk' }), NOW).events)).toEqual(['a'])
})
