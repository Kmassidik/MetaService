import { expect, test } from 'bun:test'
import { barWidth, formatBytes, formatPercent, formatProcessCpu, formatRate, formatUptime, isStale, MEASURING_TEXT, pollIntervalMs, needsHelperUpdate, offlineText, percentOf, reservedText, statsPath } from './stats.ts'
import { parseStatsReply } from './statsParse.ts'
import { UnreadableAnswer } from './machineDetail.ts'
import { workload } from './testing.ts'
import type { MachineStats, MachineStatsReply } from './types.ts'

const GIB = 1024 ** 3

export const sampleStats = (extra: Partial<MachineStats> = {}): MachineStats => ({
  taken_at: '2026-10-21T10:00:00Z', measuring: false, uptime_seconds: 90000,
  cpu: { core_count: 2, total_percent: 12.5, cores_percent: [10, 15], load: { one: 1.2, five: 0.9, fifteen: 0.7 } },
  memory: { total_bytes: 8 * GIB, used_bytes: 4 * GIB, cached_bytes: 2 * GIB, free_bytes: 2 * GIB, swap_total_bytes: 0, swap_used_bytes: 0 },
  disks: [{ mount: '/', name: 'Main', fs: 'apfs', total_bytes: 100 * GIB, used_bytes: 40 * GIB, free_bytes: 60 * GIB }],
  network: { received_total_bytes: 1000, sent_total_bytes: 500, received_bytes_per_second: 2048, sent_bytes_per_second: 512 },
  gpus: [], processes: [{ pid: 4, name: 'node', user: 'kurnia', cpu_percent: 30.04, memory_bytes: 1048576 }], ...extra,
})

const reply = (extra: Partial<MachineStatsReply> = {}): MachineStatsReply => ({ state: 'online', last_seen: '2026-10-21T10:00:00Z', fetched_at: '2026-10-21T10:00:00Z', stats: sampleStats(), ...extra })

test('bytes are written in units of 1024 with the panel\'s names', () => {
  expect(formatBytes(0)).toBe('0 B')
  expect(formatBytes(1536)).toBe('1.5 KB')
  expect(formatBytes(8 * GIB)).toBe('8 GB')
  expect(formatBytes(-5)).toBe('0 B')
})

test('a rate that is not known yet says measuring, never zero', () => {
  expect(formatRate(null)).toBe(MEASURING_TEXT)
  expect(formatRate(2048)).toBe('2 KB/s')
  expect(formatPercent(null)).toBe('–')
  expect(formatPercent(12.5)).toBe('13%')
  expect(formatProcessCpu(null)).toBe('–')
  expect(formatProcessCpu(120.04)).toBe('120.0%')
})

test('uptime shows the two biggest units', () => {
  expect(formatUptime(59)).toBe('0m')
  expect(formatUptime(3 * 3600 + 120)).toBe('3h 2m')
  expect(formatUptime(90000)).toBe('1d 1h')
})

test('percent and bar width stay between 0 and 100', () => {
  expect(percentOf(1, 4)).toBe(25)
  expect(percentOf(5, 0)).toBe(0)
  expect(percentOf(9, 4)).toBe(100)
  expect(barWidth(null)).toBe('0%')
  expect(barWidth(150)).toBe('100%')
  expect(barWidth(-3)).toBe('0%')
  expect(barWidth(33.33)).toBe('33.3%')
})

test('an offline reply is stale and says when the machine was last seen', () => {
  const offline = reply({ state: 'offline', last_seen: '2026-10-21T09:57:00Z' })
  expect(isStale(offline)).toBe(true)
  expect(isStale(reply())).toBe(false)
  expect(offlineText(offline, Date.parse('2026-10-21T10:00:00Z'))).toBe('offline, last seen 3m ago')
  expect(needsHelperUpdate(reply({ state: 'old_helper', stats: null }))).toBe(true)
})

test('the reserved line counts running cores and memory, and every disk', () => {
  expect(reservedText([])).toBe('No VMs have reserved anything yet.')
  const text = reservedText([workload({ cpu: 2, ram_mb: 4096, disk_gb: 40 }), workload({ id: 'w2', state: 'stopped', cpu: 2, ram_mb: 4096, disk_gb: 40 })])
  expect(text).toBe('VMs have reserved 2 cores, 4 GB memory, 80 GB disk')
})

test('the reply parser accepts a good reply and a missing gpu list', () => {
  const parsed = parseStatsReply(JSON.parse(JSON.stringify(reply())))
  expect(parsed.stats?.gpus).toEqual([])
  expect(parseStatsReply({ state: 'offline', last_seen: null, fetched_at: null, stats: null }).stats).toBeNull()
})

test('the reply parser refuses odd shapes', () => {
  expect(() => parseStatsReply(null)).toThrow(UnreadableAnswer)
  expect(() => parseStatsReply({ state: 'weird', stats: null })).toThrow(UnreadableAnswer)
  expect(() => parseStatsReply({ ...reply(), stats: { ...sampleStats(), uptime_seconds: 'x' } })).toThrow(UnreadableAnswer)
})

test('a watched Live tab asks every 2 seconds, after a failure every 5, and nobody watching asks nothing', () => {
  expect(pollIntervalMs({ liveTabVisible: true, pageVisible: true, failed: false })).toBe(2000)
  expect(pollIntervalMs({ liveTabVisible: true, pageVisible: true, failed: true })).toBe(5000)
  expect(pollIntervalMs({ liveTabVisible: true, pageVisible: false, failed: false })).toBeNull()
  expect(pollIntervalMs({ liveTabVisible: false, pageVisible: true, failed: false })).toBeNull()
  expect(pollIntervalMs({ liveTabVisible: false, pageVisible: false, failed: true })).toBeNull()
})

test('the stats address says whether the list of programs is wanted', () => {
  expect(statsPath('mac mini', false)).toBe('/api/machines/mac%20mini/stats?processes=0')
  expect(statsPath('studio', true)).toBe('/api/machines/studio/stats?processes=1')
})
