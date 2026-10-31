import { expect, test } from 'bun:test'
import { MAX_DAILY_POINTS, MAX_EVENTS_PER_PAGE, MAX_MACHINES, parseEvents, parseOverview } from './securityParse.ts'
import { MAX_DETAIL, MAX_TEXT } from './securityPrims.ts'
import { UnreadableAnswer } from './unreadable.ts'

const line = { machine: 'rtx-pc', reported: true, last_reported: '2026-11-01T10:00:00Z', baseline: { password_login: false, ban_tool: 'running', firewall: true }, failed: 96000, blocked: 24 }

test('a good overview is read as it was sent', () => {
  const overview = parseOverview({ range: '30d', generated_at: '2026-11-01T10:00:00Z', machines: [line], blocked_now: [{ machine: 'rtx-pc', address: '203.0.113.9', since: '2026-11-01T08:00:00Z', until: null, attempts: 6 }],
    top_users: [{ name: 'ubuntu', count: 5 }], top_addresses: [{ name: '203.0.113.9', count: 9 }], daily: [{ day: '2026-10-31', machine: 'rtx-pc', failed: 4 }] })
  expect(overview.range).toBe('30d')
  expect(overview.machines[0]).toMatchObject({ machine: 'rtx-pc', reported: true, failed: 96000, blocked: 24 })
  expect(overview.machines[0]?.baseline.pending_updates).toBeNull()
  expect(overview.blocked_now[0]?.until).toBeNull()
  expect(overview.daily).toHaveLength(1)
})

test('something that is not an object cannot be read', () => {
  for (const value of [null, 'x', 5, [], undefined]) {
    expect(() => parseOverview(value)).toThrow(UnreadableAnswer)
    expect(() => parseEvents(value)).toThrow(UnreadableAnswer)
  }
})

test('wrong types are dropped to unknown, never to zero', () => {
  const overview = parseOverview({ machines: [{ ...line, failed: '96000', blocked: -3, baseline: { firewall: 'yes', pending_updates: 1.5 } }] })
  const read = overview.machines[0]
  expect(read?.failed).toBeNull()
  expect(read?.blocked).toBeNull()
  expect(read?.baseline.firewall).toBeNull()
  expect(read?.baseline.pending_updates).toBeNull()
})

test('a machine counts as reported only when the parent says so and gives a time', () => {
  const read = (extra: Record<string, unknown>) => parseOverview({ machines: [{ ...line, ...extra }] }).machines[0]?.reported
  expect(read({})).toBe(true)
  expect(read({ reported: false })).toBe(false)
  expect(read({ last_reported: null })).toBe(false)
  expect(read({ last_reported: 'not a date' })).toBe(false)
  expect(read({ reported: 'true' })).toBe(false)
})

test('rows that cannot be read are left out, lists that are not lists are empty', () => {
  const overview = parseOverview({ machines: [line, 5, null, { reported: true }], blocked_now: 'x', top_users: [{ name: 'a' }, { name: 'b', count: 2 }], daily: [{ day: 'yesterday', machine: 'a', failed: 1 }] })
  expect(overview.machines).toHaveLength(1)
  expect(overview.blocked_now).toEqual([])
  expect(overview.top_users).toEqual([{ name: 'b', count: 2 }])
  expect(overview.daily).toEqual([])
})

test('an unknown range falls back to the default', () => {
  expect(parseOverview({ range: '5y' }).range).toBe('7d')
})

test('lists are capped', () => {
  const many = (count: number, make: (index: number) => unknown) => Array.from({ length: count }, (_, index) => make(index))
  const overview = parseOverview({ machines: many(500, (index) => ({ ...line, machine: `m${index}` })), daily: many(MAX_DAILY_POINTS + 10, () => ({ day: '2026-10-31', machine: 'a', failed: 1 })) })
  expect(overview.machines).toHaveLength(MAX_MACHINES)
  expect(overview.daily).toHaveLength(MAX_DAILY_POINTS)
  const events = parseEvents({ events: many(MAX_EVENTS_PER_PAGE + 20, (index) => ({ id: `e${index}`, time: '2026-11-01T10:00:00Z', machine: 'a', type: 'blocked' })) })
  expect(events.events).toHaveLength(MAX_EVENTS_PER_PAGE)
})

test('events: a good row is read, a row with an unknown type, no id or a bad time is left out', () => {
  const good = { id: 'e1', time: '2026-11-01T10:00:00Z', machine: 'rtx-pc', type: 'failed_login', user: 'root', address: '203.0.113.9', detail: 'invalid user', count: 120 }
  const page = parseEvents({ events: [good, { ...good, id: 'e2', type: 'nope' }, { ...good, id: '' }, { ...good, id: 'e4', time: 'x' }, { ...good, id: 'e5', method: 'password', type: 'login', count: 'many' }], next_cursor: 'abc' })
  expect(page.events.map((event) => event.id)).toEqual(['e1', 'e5'])
  expect(page.events[1]).toMatchObject({ method: 'password', count: null })
  expect(page.next_cursor).toBe('abc')
  expect(parseEvents({ events: [] }).next_cursor).toBeNull()
})

test('helper text is plain text of limited length, with no control characters', () => {
  const hostile = '<script>window.__pwned=1</script>'
  const page = parseEvents({ events: [{ id: 'e1', time: '2026-11-01T10:00:00Z', machine: 'a', type: 'failed_login', user: hostile, address: `${'1'.repeat(200)}`, detail: `line one\nline two\u001b[31m${'x'.repeat(500)}` }] })
  const event = page.events[0]
  expect(event?.user).toBe(hostile)
  expect(event?.address?.length).toBe(MAX_TEXT)
  expect(event?.address?.endsWith('…')).toBe(true)
  expect(event?.detail?.length).toBe(MAX_DETAIL)
  expect(event?.detail).not.toMatch(/[\u0000-\u001f]/)
})
