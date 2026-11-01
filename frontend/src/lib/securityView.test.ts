import { expect, test } from 'bun:test'
import { chartData, chartDays, barShare } from './securityChart.ts'
import { machineRows, nameOf, topShares, topShown, TOP_SHOWN, type MachineInfo } from './securityView.ts'
import type { SecurityOverview } from './securityTypes.ts'

const NOW = Date.parse('2026-11-01T12:00:00Z')
const infos: MachineInfo[] = [
  { id: 'a', name: 'Alpha', state: 'online', os: 'linux' }, { id: 'b', name: 'Beta', state: 'offline', os: 'linux' }, { id: 'c', name: 'Gamma', state: 'online', os: 'macos' },
]

function overview(extra: Partial<SecurityOverview> = {}): SecurityOverview {
  return {
    range: '7d', generated_at: null, blocked_now: [], top_users: [], top_addresses: [], daily: [], buckets: [], bucket_minutes: null,
    machines: [{ machine: 'a', reported: true, last_reported: '2026-11-01T11:00:00Z', baseline: { password_login: true, ban_tool: 'running', firewall: null, auto_updates: true, starts_after_reboot: true, pending_updates: 0 }, failed: 12, blocked: 0 }],
    ...extra,
  }
}

test('every machine the panel knows has a row, in the panel order', () => {
  expect(machineRows(infos, overview()).map((row) => row.id)).toEqual(['a', 'b', 'c'])
})

test('a machine that has not reported is not watched: no checks, no counts (not zeros)', () => {
  const [, beta, gamma] = machineRows(infos, overview())
  for (const row of [beta, gamma]) expect(row).toMatchObject({ watched: false, lastReported: null, checks: [], failed: null, blocked: null })
})

test('a machine the parent says has not reported is not watched either, even with numbers', () => {
  const rows = machineRows(infos, overview({ machines: [{ machine: 'a', reported: false, last_reported: null, baseline: { password_login: null, ban_tool: null, firewall: null, auto_updates: null, starts_after_reboot: null, pending_updates: null }, failed: 7, blocked: 7 }] }))
  expect(rows[0]).toMatchObject({ watched: false, failed: null, blocked: null })
})

test('a watched machine has six checks, and a blocked count of zero stays zero', () => {
  const alpha = machineRows(infos, overview())[0]
  expect(alpha?.watched).toBe(true)
  expect(alpha?.checks.map((check) => check.state)).toEqual(['warning', 'ok', 'unknown', 'ok', 'ok', 'ok'])
  expect(alpha?.blocked).toBe(0)
})

test('with no overview at all (the parent has no security API) every machine is not watched', () => {
  expect(machineRows(infos, null).every((row) => !row.watched)).toBe(true)
})

test('a machine id that is not in the list shows as the id', () => {
  expect(nameOf(infos, 'a')).toBe('Alpha')
  expect(nameOf(infos, 'zzz')).toBe('zzz')
})

test('the top lists show the biggest eight, with bars relative to the biggest', () => {
  const rows = Array.from({ length: 12 }, (_, index) => ({ name: `n${index}`, count: index + 1 }))
  const shown = topShown(rows)
  expect(shown).toHaveLength(TOP_SHOWN)
  expect(shown[0]?.name).toBe('n11')
  expect(topShares(shown)[0]).toBe(1)
  expect(topShares([])).toEqual([])
})

test('the chart covers at least 7 days ending today, and a long range covers all its days', () => {
  expect(chartDays('24h', NOW)).toHaveLength(7)
  expect(chartDays('24h', NOW).at(-1)).toBe('2026-11-01')
  expect(chartDays('90d', NOW)).toHaveLength(90)
})

test('the chart is drawn to scale from zero on one shared scale, and a day with no count has no bar', () => {
  const daily = [{ day: '2026-11-01', machine: 'a', failed: 100 }, { day: '2026-10-31', machine: 'a', failed: 50 }, { day: '2026-11-01', machine: 'c', failed: 25 }]
  const data = chartData(daily, infos, '7d', NOW)
  expect(data.series.map((one) => one.id)).toEqual(['a', 'c'])
  expect(data.tallest).toBe(100)
  expect(data.series[0]?.days.at(-1)).toBe(100)
  expect(data.series[0]?.days.at(-3)).toBeNull()
  expect(data.series[0]?.total).toBe(150)
  expect(barShare(25, data.tallest)).toBe(0.25)
  expect(barShare(null, data.tallest)).toBeNull()
  expect(barShare(0, 0)).toBe(0)
})
