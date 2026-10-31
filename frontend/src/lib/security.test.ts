import { expect, test } from 'bun:test'
import { CHART_DAYS, MAX_ROWS, MAX_TEXT, readSecurity } from './security.ts'

const healthy = {
  baseline: { password_login: false, ban_tool: 'running', firewall: true, auto_updates: true, starts_after_reboot: true, pending_updates: 0 },
  windows: { h24: { failed: 10, blocked: 1 }, d7: { failed: 70, blocked: 3 }, d30: { failed: 300, blocked: 9 } },
  daily_failed: [1, 2, 3],
  blocked: [{ address: '203.0.113.9', since: '2026-10-30T10:00:00Z', until: '2026-10-31T10:00:00Z', attempts: 6 }],
  usernames: [{ name: 'admin', count: 40 }],
  logins: [{ method: 'key', user: 'kurnia', address: '198.51.100.4', count: 3, last_seen: '2026-10-31T09:00:00Z' }],
}

test('a good report is read as it was sent', () => {
  const report = readSecurity(healthy)
  expect(report?.baseline.ban_tool).toBe('running')
  expect(report?.windows.d7).toEqual({ failed: 70, blocked: 3 })
  expect(report?.blocked[0]?.attempts).toBe(6)
  expect(report?.logins[0]?.method).toBe('key')
})

test('no report, or something that is not an object, is "not reporting"', () => {
  for (const value of [undefined, null, 'x', 5, [], true]) expect(readSecurity(value)).toBeNull()
})

test('an empty report says nothing, so it is not reporting either (no fake zeros)', () => {
  expect(readSecurity({})).toBeNull()
  expect(readSecurity({ baseline: {}, windows: {}, daily_failed: [], blocked: [] })).toBeNull()
})

test('wrong types are dropped to unknown, not turned into zero or false', () => {
  const report = readSecurity({ ...healthy, baseline: { password_login: 'no', ban_tool: 'weird', firewall: 1, pending_updates: -3, auto_updates: true }, windows: { h24: { failed: '9', blocked: 1.5 } } })
  expect(report?.baseline.password_login).toBeNull()
  expect(report?.baseline.ban_tool).toBeNull()
  expect(report?.baseline.firewall).toBeNull()
  expect(report?.baseline.pending_updates).toBeNull()
  expect(report?.baseline.auto_updates).toBe(true)
  expect(report?.windows.h24).toEqual({ failed: null, blocked: null })
  expect(report?.windows.d30).toEqual({ failed: null, blocked: null })
})

test('rows with a wrong shape are left out, good rows stay', () => {
  const report = readSecurity({
    ...healthy,
    blocked: [null, 5, { address: 7 }, { address: '' }, { address: '1.2.3.4' }],
    usernames: [{ name: 'root' }, { name: 'ubuntu', count: 'x' }, { name: 'test', count: 4 }],
    logins: [{ method: 'telepathy', user: 'a', address: 'b', count: 1 }, { method: 'password', user: 'a', address: 'b', count: 1 }],
  })
  expect(report?.blocked.map((row) => row.address)).toEqual(['1.2.3.4'])
  expect(report?.usernames).toEqual([{ name: 'test', count: 4 }])
  expect(report?.logins.length).toBe(1)
})

test('hostile text stays text: control characters go, length is cut, markup is not interpreted', () => {
  const hostile = '<script>alert(1)</script>'
  const long = 'a'.repeat(500)
  const report = readSecurity({ ...healthy, usernames: [{ name: hostile, count: 2 }, { name: 'x\u0000y\nz\u001b[31m', count: 1 }, { name: long, count: 1 }] })
  expect(report?.usernames[0]?.name).toBe(hostile)
  expect(report?.usernames[1]?.name).toBe('x y z [31m')
  expect(report?.usernames[2]?.name.length).toBe(MAX_TEXT)
  expect(report?.usernames[2]?.name.endsWith('…')).toBe(true)
})

test('lists are capped at 50 rows and the chart at the last 30 days', () => {
  const many = Array.from({ length: 200 }, (_, index) => ({ address: `10.0.0.${index}`, since: null, until: null, attempts: 1 }))
  const days = Array.from({ length: 90 }, (_, index) => index)
  const report = readSecurity({ ...healthy, blocked: many, daily_failed: days })
  expect(report?.blocked.length).toBe(MAX_ROWS)
  expect(report?.daily_failed.length).toBe(CHART_DAYS)
  expect(report?.daily_failed.at(-1)).toBe(89)
})

test('a day that is not a count is null, a date that does not parse is dropped', () => {
  const report = readSecurity({ ...healthy, daily_failed: [3, 'x', -1, 2.5, 4], blocked: [{ address: 'a', since: 'yesterday-ish', until: null, attempts: 1 }] })
  expect(report?.daily_failed).toEqual([3, null, null, null, 4])
  expect(report?.blocked[0]?.since).toBeNull()
})
