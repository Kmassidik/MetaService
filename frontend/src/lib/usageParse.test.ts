import { expect, test } from 'bun:test'
import { DAY_SECONDS, MAX_DAYS, MAX_MACHINES, MAX_TEXT, fillDays, formatBytes, formatRate, formatShare, parseUsage, parseUsageDaily, type UsageDay } from './usageParse.ts'

const machine = (extra: Record<string, unknown> = {}) => ({
  machine_id: 'm1', name: 'Mini', in_bytes: 2000, out_bytes: 500, in_peak_bps: 300, out_peak_bps: 40, ...extra,
})
const answer = (extra: Record<string, unknown> = {}) => ({
  range: 'today', since: 1000, machines: [machine()], total: { in_bytes: 2000, out_bytes: 500 }, ...extra,
})
const day = (dayStart: number, extra: Partial<UsageDay> = {}): UsageDay => ({ dayStart, inBytes: 1, outBytes: 2, inPeakBps: 3, outPeakBps: 4, ...extra })

test('a normal usage answer is read field by field, camelCase', () => {
  expect(parseUsage(answer())).toEqual({
    range: 'today',
    since: 1000,
    machines: [{ machineId: 'm1', name: 'Mini', inBytes: 2000, outBytes: 500, inPeakBps: 300, outPeakBps: 40 }],
    totalIn: 2000,
    totalOut: 500,
  })
})

test('a normal daily answer is read day by day', () => {
  expect(parseUsageDaily({ days: [{ day_start: 86400, in_bytes: 5, out_bytes: 6, in_peak_bps: 7, out_peak_bps: 8 }] })).toEqual([
    { dayStart: 86400, inBytes: 5, outBytes: 6, inPeakBps: 7, outPeakBps: 8 },
  ])
})

test('garbage input becomes an empty answer, never made-up traffic', () => {
  for (const bad of [null, undefined, 'text', 42, [], true]) {
    expect(parseUsage(bad), String(bad)).toEqual({ range: '', since: 0, machines: [], totalIn: 0, totalOut: 0 })
    expect(parseUsageDaily(bad), String(bad)).toEqual([])
  }
})

test('wrong types in the fields fall back to 0 and the empty text', () => {
  const odd = parseUsage(answer({ range: 5, since: '7', machines: [machine({ machine_id: null, name: {}, in_bytes: '2', out_bytes: true, in_peak_bps: [], out_peak_bps: 'x' })], total: 'all' }))
  expect(odd.range).toBe('')
  expect(odd.since).toBe(0)
  expect(odd.totalIn).toBe(0)
  expect(odd.machines).toEqual([{ machineId: '', name: '', inBytes: 0, outBytes: 0, inPeakBps: 0, outPeakBps: 0 }])
})

test('negative and NaN numbers become 0', () => {
  const bad = parseUsage(answer({ since: -5, total: { in_bytes: -1, out_bytes: NaN }, machines: [machine({ in_bytes: -100, out_bytes: Infinity, in_peak_bps: NaN, out_peak_bps: -2 })] }))
  expect(bad.since).toBe(0)
  expect(bad.totalIn).toBe(0)
  expect(bad.totalOut).toBe(0)
  expect(bad.machines).toEqual([{ machineId: 'm1', name: 'Mini', inBytes: 0, outBytes: 0, inPeakBps: 0, outPeakBps: 0 }])
})

test('rows that are not objects are left out of the lists', () => {
  const parsed = parseUsage(answer({ machines: [null, 'row', 3, [], machine()] }))
  expect(parsed.machines.map((row) => row.machineId)).toEqual(['m1'])
  expect(parseUsageDaily({ days: [null, 'x', { day_start: 1 }] })).toEqual([{ dayStart: 1, inBytes: 0, outBytes: 0, inPeakBps: 0, outPeakBps: 0 }])
})

test('control characters are removed from names and text is cut at the limit', () => {
  const parsed = parseUsage(answer({ range: 'to\u0000day\n', machines: [machine({ name: 'a\u0007b\u009fc', machine_id: 'x'.repeat(MAX_TEXT + 40) })] }))
  expect(parsed.range).toBe('today')
  expect(parsed.machines.map((row) => row.name)).toEqual(['abc'])
  expect(parsed.machines.map((row) => row.machineId.length)).toEqual([MAX_TEXT])
})

test('machines are capped at 256 and days at 31', () => {
  const machines = Array.from({ length: MAX_MACHINES + 10 }, (_, index) => machine({ machine_id: `m${index}` }))
  expect(parseUsage(answer({ machines })).machines.length).toBe(MAX_MACHINES)
  const days = Array.from({ length: MAX_DAYS + 5 }, (_, index) => ({ day_start: index }))
  expect(parseUsageDaily({ days }).length).toBe(MAX_DAYS)
})

test('bytes are formatted in decimal steps, with no decimals below a gigabyte', () => {
  expect(formatBytes(0)).toBe('0 B')
  expect(formatBytes(999)).toBe('999 B')
  expect(formatBytes(1000)).toBe('1 KB')
  expect(formatBytes(1500)).toBe('2 KB')
  expect(formatBytes(999_000)).toBe('999 KB')
  expect(formatBytes(999_999)).toBe('1 MB')
  expect(formatBytes(999_960_000)).toBe('1.0 GB')
  expect(formatBytes(1_000_000)).toBe('1 MB')
  expect(formatBytes(12_000_000)).toBe('12 MB')
  expect(formatBytes(1_200_000_000)).toBe('1.2 GB')
  expect(formatBytes(3_400_000_000_000)).toBe('3.4 TB')
})

test('a negative, NaN or fractional byte count is shown as a whole number of bytes', () => {
  expect(formatBytes(-4)).toBe('0 B')
  expect(formatBytes(NaN)).toBe('0 B')
  expect(formatBytes(2.6)).toBe('3 B')
})

test('rates are megabits per second from one megabit up, kilobits below', () => {
  expect(formatRate(0)).toBe('0 kbit/s')
  expect(formatRate(64_000)).toBe('512 kbit/s')
  expect(formatRate(124_000)).toBe('992 kbit/s')
  expect(formatRate(125_000)).toBe('1.0 Mbit/s')
  expect(formatRate(1_537_500)).toBe('12.3 Mbit/s')
  expect(formatRate(NaN)).toBe('0 kbit/s')
})

test('a share is a percent with one decimal, and 0 % when the whole is empty', () => {
  expect(formatShare(1, 8)).toBe('12.5 %')
  expect(formatShare(0, 8)).toBe('0.0 %')
  expect(formatShare(5, 0)).toBe('0 %')
  expect(formatShare(-3, 10)).toBe('0.0 %')
})

test('fillDays returns exactly the count, oldest first, with zeros for missing days', () => {
  const today = 10 * DAY_SECONDS
  const filled = fillDays([day(today - 2 * DAY_SECONDS, { inBytes: 9, outBytes: 0 })], 4, today)
  expect(filled.map((row) => row.dayStart)).toEqual([7 * DAY_SECONDS, 8 * DAY_SECONDS, 9 * DAY_SECONDS, today])
  expect(filled.map((row) => row.inBytes)).toEqual([0, 9, 0, 0])
  expect(filled.map((row) => row.outBytes)).toEqual([0, 0, 0, 0])
})

test('fillDays with no data gives all zeros, and days outside the window are dropped', () => {
  const today = 100 * DAY_SECONDS
  expect(fillDays([], 7, today).length).toBe(7)
  expect(fillDays([], 7, today).every((row) => row.inBytes === 0 && row.outPeakBps === 0)).toBe(true)
  const outside = fillDays([day(today + DAY_SECONDS), day(today - 30 * DAY_SECONDS)], 7, today)
  expect(outside.every((row) => row.inBytes === 1 || row.inBytes === 0)).toBe(true)
  expect(outside.filter((row) => row.inBytes === 1).length).toBe(0)
})

test('fillDays keeps the figures of a day that has data', () => {
  const today = 50 * DAY_SECONDS
  const [, , last] = fillDays([day(today, { inBytes: 11, outBytes: 22, inPeakBps: 33, outPeakBps: 44 })], 3, today)
  expect(last).toEqual({ dayStart: today, inBytes: 11, outBytes: 22, inPeakBps: 33, outPeakBps: 44 })
})
