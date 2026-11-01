import { expect, test } from 'bun:test'
import { MAX_BUCKET_POINTS, MAX_MACHINES, parseOverview } from './securityParse.ts'
import { bucketChart, bucketStarts, bucketTicks } from './securityBuckets.ts'
import { RANGE_PHRASE, TICK_MINUTES, bucketMinutesOf, isShortRange } from './securityRanges.ts'
import { RANGES, RANGE_LABELS, type BucketFailed } from './securityTypes.ts'
import { clockLabel } from './securityTime.ts'
import { machineRows, notWatchedLine, rangeSummary, infoOf, NOT_WATCHED_LINE, OFFLINE_LINE, type MachineInfo } from './securityView.ts'
import { cardUpdate } from './helperUpdate.ts'
import type { Machine } from './types.ts'

const NOW = Date.parse('2026-11-01T08:53:20Z')
const JAKARTA = 'Asia/Jakarta'
const infos: MachineInfo[] = [{ id: 'a', name: 'Alpha', state: 'online', os: 'linux' }, { id: 'm', name: 'Mac', state: 'online', os: 'macos' }]

test('the page offers the seven ranges in order, each with a label and wording', () => {
  expect(RANGES.map((range) => RANGE_LABELS[range])).toEqual(['1 h', '6 h', '12 h', '24 h', '7 d', '30 d', '90 d'])
  expect(RANGE_PHRASE['6h']).toBe('in the last 6 hours')
  expect(RANGE_PHRASE['1h']).toBe('in the last hour')
  expect(RANGES.filter(isShortRange)).toEqual(['1h', '6h', '12h', '24h'])
})

test('a chart holds 6, 36, 72 or 144 buckets and ends with the one that now falls in', () => {
  for (const [range, count] of [['1h', 6], ['6h', 36], ['12h', 72], ['24h', 144]] as const) {
    const starts = bucketStarts(range, NOW, 10)
    expect(starts).toHaveLength(count)
    expect(new Date(starts.at(-1) ?? 0).toISOString()).toBe('2026-11-01T08:50:00.000Z')
  }
  expect(new Date(bucketStarts('1h', NOW, 10)[0] ?? 0).toISOString()).toBe('2026-11-01T08:00:00.000Z')
})

test('a moment exactly on a bucket boundary starts a new bucket', () => {
  const starts = bucketStarts('1h', Date.parse('2026-11-01T09:00:00Z'), 10)
  expect(new Date(starts.at(-1) ?? 0).toISOString()).toBe('2026-11-01T09:00:00.000Z')
})

test('ticks: 1 h every 10 minutes, 6 h every hour, 12 h every 2 hours, 24 h every 3 hours, on the viewer clock', () => {
  const ticks = (range: '1h' | '6h' | '12h' | '24h', zone: string) => bucketTicks(bucketStarts(range, NOW, 10), range, zone)
  expect(ticks('1h', 'UTC').map((tick) => tick.label)).toEqual(['08:00', '08:10', '08:20', '08:30', '08:40', '08:50'])
  expect(ticks('1h', JAKARTA).map((tick) => tick.label)).toEqual(['15:00', '15:10', '15:20', '15:30', '15:40', '15:50'])
  expect(ticks('6h', JAKARTA).map((tick) => tick.label)).toEqual(['10:00', '11:00', '12:00', '13:00', '14:00', '15:00'])
  expect(ticks('12h', JAKARTA).map((tick) => tick.label)).toEqual(['04:00', '06:00', '08:00', '10:00', '12:00', '14:00'])
  expect(ticks('24h', JAKARTA).map((tick) => tick.label)).toEqual(['18:00', '21:00', '00:00', '03:00', '06:00', '09:00', '12:00', '15:00'])
  expect(TICK_MINUTES['24h']).toBe(180)
})

test('a half-hour zone puts the ticks on its own whole hours', () => {
  const labels = bucketTicks(bucketStarts('6h', NOW, 10), '6h', 'Asia/Kolkata').map((tick) => tick.label)
  expect(labels.every((label) => label.endsWith(':00'))).toBe(true)
  expect(clockLabel(NOW, 'Asia/Kolkata')).toBe('14:23')
})

const at = (time: string, machine: string, failed: number | null): BucketFailed => ({ start: `2026-11-01T${time}:00Z`, machine, failed })

test('bars are placed by bucket, a missing bucket has no bar (null), and all machines share the tallest', () => {
  const chart = bucketChart([at('08:50', 'a', 4), at('08:30', 'a', 9), at('08:50', 'm', 20)], infos, '1h', NOW, JAKARTA, 10)
  expect(chart.series.map((one) => one.id)).toEqual(['a', 'm'])
  expect(chart.series[0]?.counts).toEqual([null, null, null, 9, null, 4])
  expect(chart.series[1]?.counts).toEqual([null, null, null, null, null, 20])
  expect(chart.series[1]?.connections).toBe(true)
  expect(chart.series[0]?.total).toBe(13)
  expect(chart.tallest).toBe(20)
})

test('buckets outside the range, unknown counts and unwatched machines are left out', () => {
  const chart = bucketChart([at('07:40', 'a', 5), at('08:50', 'a', null), at('08:50', 'ghost', 7), at('08:20', 'a', 2)], infos, '1h', NOW, 'UTC', 10)
  expect(chart.series).toHaveLength(1)
  expect(chart.series[0]?.counts).toEqual([null, null, 2, null, null, null])
  expect(bucketChart([], infos, '24h', NOW, 'UTC', 10).series).toEqual([])
})

test('two rows of one bucket are added', () => {
  const chart = bucketChart([at('08:50', 'a', 4), at('08:50', 'a', 3)], infos, '1h', NOW, 'UTC', 10)
  expect(chart.series[0]?.counts.at(-1)).toBe(7)
})

test('the bucket length is the parent’s when it makes sense, else ten minutes', () => {
  expect([null, 10, 5, 7, 0, 90, 20].map(bucketMinutesOf)).toEqual([10, 10, 5, 10, 10, 10, 20])
})

test('the overview parser keeps buckets and their length; wrong types are dropped to unknown', () => {
  const overview = parseOverview({ range: '1h', buckets: [{ start: '2026-11-01T08:50:00Z', machine: 'a', failed: 4 }, { start: 'nope', machine: 'a', failed: 1 }, { start: '2026-11-01T08:40:00Z', machine: 'a', failed: '3' }, 7], bucket_minutes: 10 })
  expect(overview.range).toBe('1h')
  expect(overview.buckets).toEqual([{ start: '2026-11-01T08:50:00Z', machine: 'a', failed: 4 }, { start: '2026-11-01T08:40:00Z', machine: 'a', failed: null }])
  expect(overview.bucket_minutes).toBe(10)
  const old = parseOverview({ range: '7d', daily: [] })
  expect(old.buckets).toEqual([])
  expect(old.bucket_minutes).toBeNull()
  expect(parseOverview({ bucket_minutes: '10' }).bucket_minutes).toBeNull()
})

test('buckets are capped at 144 for each machine the panel keeps', () => {
  const many = Array.from({ length: MAX_BUCKET_POINTS + 50 }, () => ({ start: '2026-11-01T08:50:00Z', machine: 'a', failed: 1 }))
  expect(parseOverview({ buckets: many }).buckets).toHaveLength(MAX_BUCKET_POINTS)
  expect(MAX_BUCKET_POINTS).toBe(144 * MAX_MACHINES)
})

function row(machine: string, failed: number) {
  return { machine, reported: true, last_reported: '2026-11-01T08:50:00Z', baseline: { password_login: null, ban_tool: null, firewall: null, auto_updates: null, starts_after_reboot: null, pending_updates: null }, failed, blocked: 0 }
}

test('the summary uses the range wording and counts Macs as connections', () => {
  const rows = machineRows(infos, { range: '6h', generated_at: null, machines: [row('a', 1200), row('m', 1)], blocked_now: [], top_users: [], top_addresses: [], daily: [], buckets: [], bucket_minutes: 10 })
  expect(rangeSummary(rows, '6h')).toBe('1,200 failed logins and 1 SSH connection in the last 6 hours.')
  expect(rangeSummary(rows, '1h')?.endsWith('in the last hour.')).toBe(true)
  expect(rangeSummary(machineRows(infos, null), '6h')).toBeNull()
})

function machine(state: Machine['state'], extra: Partial<Machine> = {}): Machine {
  return { id: 'x', name: 'X', state, os: 'linux', ...extra } as Machine
}

test('Not watched rows: a line for an online machine, the offline line for an offline one', () => {
  expect(notWatchedLine({ state: 'online' })).toBe(NOT_WATCHED_LINE)
  expect(notWatchedLine({ state: 'busy' })).toBe(NOT_WATCHED_LINE)
  expect(notWatchedLine({ state: 'offline' })).toBe(OFFLINE_LINE)
  expect(NOT_WATCHED_LINE).toBe('No security data yet: its helper may be old')
})

test('the Update helper button shows only for an online machine with an update on offer', () => {
  const update = { available: true, current_build: 'aaaa', newest_build: 'bbbb', reason: null }
  const [online] = infoOf([machine('online', { agent_build: 'aaaa', update })])
  const [offline] = infoOf([machine('offline', { agent_build: 'aaaa', update })])
  const [current] = infoOf([machine('online', { agent_build: 'aaaa', update: { ...update, available: false } })])
  const [silent] = infoOf([machine('online')])
  expect(cardUpdate(online as MachineInfo).button).toBe(true)
  expect(cardUpdate(offline as MachineInfo).button).toBe(false)
  expect(cardUpdate(current as MachineInfo).button).toBe(false)
  expect(cardUpdate(silent as MachineInfo).button).toBe(false)
})
