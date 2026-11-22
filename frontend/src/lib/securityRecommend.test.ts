import { expect, test } from 'bun:test'
import { networkOf, recommendations } from './securityRecommend.ts'
import type { SecurityMachineLine } from './securityTypes.ts'

const baseline = { password_login: null, ban_tool: null, firewall: null, auto_updates: null, starts_after_reboot: null, pending_updates: null }
const line = (over: Partial<SecurityMachineLine> = {}): SecurityMachineLine => ({
  machine: 'mac', reported: true, last_reported: null, baseline: { ...baseline }, failed: 0, blocked: 0, ...over,
})

test('networkOf turns an IPv4 address into its /24, IPv6 stays', () => {
  expect(networkOf('185.226.94.203')).toBe('185.226.94.0/24')
  expect(networkOf('2001:db8::9')).toBe('2001:db8::9')
})

test('password login on is the top priority', () => {
  const recs = recommendations([line({ baseline: { ...baseline, password_login: true } })], [])
  expect(recs[0]?.priority).toBe(100)
  expect(recs[0]?.action).toBe('Turn password login OFF')
})

test('ban tool missing is recommended with a why', () => {
  const recs = recommendations([line({ baseline: { ...baseline, ban_tool: 'not_available' } })], [])
  expect(recs.some((r) => r.action === 'Enable the ban tool')).toBe(true)
})

test('top offenders with 50+ attempts get a router recommendation with rule text', () => {
  const recs = recommendations([line()], [{ name: '185.226.94.203', count: 500 }])
  const router = recs.find((r) => r.target === 'router')
  expect(router?.action).toBe('Block 185.226.94.0/24 at the router')
  expect(router?.omadaRule).toContain('185.226.94.0/24')
})

test('unwatched machines are skipped', () => {
  const recs = recommendations([line({ reported: false })], [])
  expect(recs).toEqual([])
})

test('recommendations sort by priority descending', () => {
  const recs = recommendations([
    line({ machine: 'a', baseline: { ...baseline, firewall: false } }),
    line({ machine: 'b', baseline: { ...baseline, password_login: true } }),
  ], [])
  expect(recs[0]?.priority).toBeGreaterThan(recs[recs.length - 1]!.priority)
})
