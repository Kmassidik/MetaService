import { expect, test } from 'bun:test'
import { readSecurity } from './security.ts'
import { barShares, baselineRows, blockEndText, blockedEmptyText, dayLabel, nameShares, numberText, orderBlocked, orderLogins, securityBadge, summaryHeadline, topNames, TOP_NAMES, warningCount } from './securityRules.ts'
import type { MachineSecurity } from './types.ts'

const base = { password_login: false, ban_tool: 'running', firewall: true, auto_updates: true, starts_after_reboot: true, pending_updates: 0 }
const counted = { h24: { failed: 5, blocked: 1 }, d7: { failed: 50, blocked: 12 }, d30: { failed: 96214, blocked: 24 } }

function report(baseline: Record<string, unknown> = {}): MachineSecurity {
  const made = readSecurity({ baseline: { ...base, ...baseline }, windows: counted, daily_failed: [1] })
  if (made === null) throw new Error('the test report is unreadable')
  return made
}

test('a healthy machine has six ok rows and no warning', () => {
  expect(baselineRows(report()).map((row) => row.state)).toEqual(['ok', 'ok', 'ok', 'ok', 'ok', 'ok'])
  expect(warningCount(report())).toBe(0)
})

test('password login on is a warning that says what to do in plain words', () => {
  const row = baselineRows(report({ password_login: true }))[0]
  expect(row?.state).toBe('warning')
  expect(row?.todo).toBe('Turn off password login')
})

test('no ban tool on Linux is a warning, but "not available" on a Mac is only unknown', () => {
  expect(baselineRows(report({ ban_tool: 'not_running' }))[1]?.state).toBe('warning')
  const mac = baselineRows(report({ ban_tool: 'not_available' }))[1]
  expect(mac?.state).toBe('unknown')
  expect(mac?.line).toContain('Not available')
  expect(mac?.todo).toBeNull()
})

test('an old helper that does not say gives unknown rows, never ok', () => {
  const rows = baselineRows(report({ password_login: null, ban_tool: null, firewall: null, auto_updates: null, starts_after_reboot: null, pending_updates: null }))
  expect(rows.every((row) => row.state === 'unknown')).toBe(true)
})

test('pending updates: zero is ok, one or more is a warning with the count', () => {
  expect(baselineRows(report({ pending_updates: 0 }))[5]?.state).toBe('ok')
  expect(baselineRows(report({ pending_updates: 1 }))[5]?.line).toBe('1 security update is waiting.')
  expect(baselineRows(report({ pending_updates: 7 }))[5]?.line).toBe('7 security updates are waiting.')
})

test('firewall, automatic updates and reboot each warn when off', () => {
  const rows = baselineRows(report({ firewall: false, auto_updates: false, starts_after_reboot: false }))
  expect(rows.filter((row) => row.state === 'warning').map((row) => row.id)).toEqual(['firewall', 'auto_updates', 'starts_after_reboot'])
})

test('numbers have separators and a missing count is a dash', () => {
  expect(numberText(96214)).toBe('96,214')
  expect(numberText(null)).toBe('–')
})

test('the headline names both counts, and says so when the window was not counted', () => {
  expect(summaryHeadline(report().windows)).toBe('96,214 failed logins and 24 blocked addresses in the last 30 days.')
  expect(summaryHeadline({ ...report().windows, d30: { failed: 1, blocked: 1 } })).toBe('1 failed login and 1 blocked address in the last 30 days.')
  expect(summaryHeadline({ ...report().windows, d30: { failed: null, blocked: null } })).toContain('not counted')
})

test('the badge: nothing when not reporting, blocked count when fine, a dot when a check warns', () => {
  expect(securityBadge(null)).toBeNull()
  expect(securityBadge(report())).toEqual({ text: '12 blocked · 7 d', warning: false })
  expect(securityBadge(report({ password_login: true }))).toEqual({ text: '● 12 blocked · 7 d', warning: true })
})

test('the empty state of the blocked table is honest about the tool', () => {
  expect(blockedEmptyText(report())).toContain('No address is blocked')
  expect(blockedEmptyText(report({ ban_tool: 'not_running' }))).toContain('does not mean nobody is knocking')
  expect(blockedEmptyText(report({ ban_tool: 'not_available' }))).toContain('nothing is blocked')
  expect(blockedEmptyText(report({ ban_tool: null }))).toContain('has not said')
})

test('blocked rows: newest first, undated last', () => {
  const rows = [{ address: 'old', since: '2026-10-01T00:00:00Z', until: null, attempts: 1 }, { address: 'none', since: null, until: null, attempts: 1 }, { address: 'new', since: '2026-10-30T00:00:00Z', until: null, attempts: 1 }]
  expect(orderBlocked(rows).map((row) => row.address)).toEqual(['new', 'old', 'none'])
})

test('the top names are the biggest eight', () => {
  const rows = Array.from({ length: 12 }, (_, index) => ({ name: `n${index}`, count: index }))
  const top = topNames(rows)
  expect(top.length).toBe(TOP_NAMES)
  expect(top[0]?.name).toBe('n11')
  expect(nameShares(top)[0]).toBe(1)
})

test('password logins come first, then the most recent', () => {
  const rows = [
    { method: 'key' as const, user: 'a', address: '1', count: 1, last_seen: '2026-10-31T00:00:00Z' },
    { method: 'password' as const, user: 'b', address: '2', count: 1, last_seen: '2026-10-01T00:00:00Z' },
    { method: 'key' as const, user: 'c', address: '3', count: 1, last_seen: '2026-10-20T00:00:00Z' },
  ]
  expect(orderLogins(rows).map((row) => row.user)).toEqual(['b', 'a', 'c'])
})

test('the end of a block reads in the future or the past, or a dash', () => {
  const now = Date.parse('2026-10-31T12:00:00Z')
  expect(blockEndText('2026-10-31T15:00:00Z', now)).toBe('in 3h')
  expect(blockEndText('2026-10-31T12:20:00Z', now)).toBe('in 20m')
  expect(blockEndText('2026-10-31T10:00:00Z', now)).toBe('ended 2h ago')
  expect(blockEndText(null, now)).toBe('–')
})

test('bars are drawn to scale from zero, an uncounted day has no bar', () => {
  expect(barShares([0, 50, 100, null])).toEqual([0, 0.5, 1, null])
  expect(barShares([0, 0])).toEqual([0, 0])
  expect(dayLabel(29, 30)).toBe('today')
  expect(dayLabel(28, 30)).toBe('yesterday')
  expect(dayLabel(0, 30)).toBe('29 days ago')
})
