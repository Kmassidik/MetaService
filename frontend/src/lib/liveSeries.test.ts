import { describe, expect, test } from 'bun:test'
import { appendPoint, CHART_POINT_LIMIT, column, dropsInWindow, mergeHistory, pointFromHistory, pointFromReading, pointsFromHistory, summarize, type LivePoint } from './liveSeries.ts'
import { parseHistoryReply } from './statsHistoryParse.ts'
import { sampleStats } from './stats.test.ts'
import type { MachineStatsReply, StatsHistoryPoint } from './types.ts'

const historyPoint = (t: number, extra: Partial<StatsHistoryPoint> = {}): StatsHistoryPoint => ({
  t, cpu_percent: 10, mem_used: 4, mem_cached: 2, mem_total: 8, swap_used: 0, swap_total: 0, net_in_bps: 100, net_out_bps: null, ...extra,
})

const live = (t: number, extra: Partial<LivePoint> = {}): LivePoint => ({ ...pointFromHistory(historyPoint(t)), ...extra })

const online = (extra: Partial<MachineStatsReply> = {}): MachineStatsReply => ({ state: 'online', last_seen: null, fetched_at: '1970-01-01T00:16:40Z', stats: sampleStats(), ...extra })

describe('history from the parent', () => {
  test('optional numbers become null, the rest is kept as it is', () => {
    const point = pointFromHistory(historyPoint(5))
    expect(point).toMatchObject({ t: 5, cpu: 10, memUsed: 4, memTotal: 8, netIn: 100, netOut: null })
    expect([point.breakdown, point.load, point.diskRead, point.diskWrite, point.drops, point.processes]).toEqual([null, null, null, null, null, null])
  })

  test('the optional numbers come through when the helper sent them', () => {
    const point = pointFromHistory(historyPoint(5, { cpu_breakdown: { user: 3 }, load: [1, 2, 3], disk_read: 7, disk_write: 8, net_drops: 9, processes_count: 400 }))
    expect(point).toMatchObject({ breakdown: { user: 3 }, load: [1, 2, 3], diskRead: 7, diskWrite: 8, drops: 9, processes: 400 })
  })

  test('at most an hour of points is kept, the newest', () => {
    const many = Array.from({ length: 500 }, (_, index) => historyPoint(index))
    const points = pointsFromHistory({ interval_seconds: 10, points: many })
    expect(points.length).toBe(CHART_POINT_LIMIT)
    expect(points[points.length - 1]?.t).toBe(499)
  })

  test('the answer of the route is checked: a missing number is unreadable, an odd optional one is left out', () => {
    const good = { interval_seconds: 10, points: [{ t: 1, cpu_percent: 2, mem_used: 3, mem_cached: 4, mem_total: 5, swap_used: 0, swap_total: 0, net_in_bps: null, net_out_bps: 1, load: [1, 2], disk_read: 'x', cpu_breakdown: { user: 1 } }] }
    const parsed = parseHistoryReply(good)
    expect(parsed.points[0]?.net_in_bps).toBeNull()
    expect(parsed.points[0]?.load).toBeUndefined()
    expect(parsed.points[0]?.disk_read).toBeUndefined()
    expect(parsed.points[0]?.cpu_breakdown).toEqual({ user: 1 })
    expect(() => parseHistoryReply({ interval_seconds: 10, points: [{ t: 1 }] })).toThrow()
    expect(() => parseHistoryReply({ points: [] })).toThrow()
    expect(() => parseHistoryReply('nope')).toThrow()
    expect(() => parseHistoryReply({ interval_seconds: 10, points: [5] })).toThrow()
  })
})

describe('a live reading', () => {
  test('becomes a point stamped with the time the parent got it', () => {
    const point = pointFromReading(online(), 0)
    expect(point?.t).toBe(1000)
    expect(point?.cpu).toBe(12.5)
    expect(point?.load).toEqual([1.2, 0.9, 0.7])
    expect(point?.netIn).toBe(2048)
    expect(point?.diskRead).toBeNull()
  })

  test('while measuring, offline or old there is no point', () => {
    const measuring = sampleStats({ cpu: { ...sampleStats().cpu, total_percent: null } })
    expect(pointFromReading(online({ stats: measuring }), 0)).toBeNull()
    expect(pointFromReading(online({ state: 'offline' }), 0)).toBeNull()
    expect(pointFromReading(online({ state: 'old_helper', stats: null }), 0)).toBeNull()
  })

  test('without a usable time the clock of the page is used', () => {
    expect(pointFromReading(online({ fetched_at: null }), 77)?.t).toBe(77)
    expect(pointFromReading(online({ fetched_at: 'not a time' }), 77)?.t).toBe(77)
  })

  test('drops in and out are added; a Mac that counts one side only still has a number; none is null', () => {
    const base = sampleStats()
    expect(pointFromReading(online({ stats: sampleStats({ network: { ...base.network, drops_in_total: 3, drops_out_total: 4 } }) }), 0)?.drops).toBe(7)
    expect(pointFromReading(online({ stats: sampleStats({ network: { ...base.network, drops_in_total: 3 } }) }), 0)?.drops).toBe(3)
    expect(pointFromReading(online(), 0)?.drops).toBeNull()
  })
})

describe('appendPoint', () => {
  test('adds a point that is about one interval newer', () => {
    expect(appendPoint([live(0)], live(10)).length).toBe(2)
    expect(appendPoint([live(0)], live(9)).length).toBe(2)
  })

  test('skips a point that is too close, repeated or older, and keeps the list as it was', () => {
    const base = [live(100)]
    expect(appendPoint(base, live(105))).toEqual(base)
    expect(appendPoint(base, live(100))).toEqual(base)
    expect(appendPoint(base, live(50))).toEqual(base)
  })

  test('the first point is always added, and the list never passes an hour', () => {
    expect(appendPoint([], live(5)).length).toBe(1)
    const full = Array.from({ length: CHART_POINT_LIMIT }, (_, index) => live(index * 10))
    const next = appendPoint(full, live(CHART_POINT_LIMIT * 10))
    expect(next.length).toBe(CHART_POINT_LIMIT)
    expect(next[0]?.t).toBe(10)
  })

  test('returns a new list, never the one it was given', () => {
    const base = [live(0)]
    expect(appendPoint(base, live(10))).not.toBe(base)
    expect(base.length).toBe(1)
  })
})

describe('summaries', () => {
  test('latest, smallest, biggest and average ignore gaps', () => {
    expect(summarize([1, null, 3, null])).toEqual({ latest: 3, min: 1, max: 3, mean: 2 })
    expect(summarize([null, null])).toEqual({ latest: null, min: null, max: null, mean: null })
    expect(summarize([])).toEqual({ latest: null, min: null, max: null, mean: null })
  })

  test('a column keeps the gaps', () => {
    expect(column([live(0), live(10, { netIn: null })], (point) => point.netIn)).toEqual([100, null])
  })

  test('drops in the window are the change of the running total, or unknown', () => {
    expect(dropsInWindow([live(0, { drops: 5 }), live(10, { drops: 9 })])).toBe(4)
    expect(dropsInWindow([live(0), live(10)])).toBeNull()
    expect(dropsInWindow([live(0, { drops: 9 }), live(10, { drops: 2 })])).toBeNull()
    expect(dropsInWindow([])).toBeNull()
  })
})

describe('mergeHistory', () => {
  test('the history first, then only the live points that are newer', () => {
    const merged = mergeHistory([live(0), live(10)], [live(5), live(10), live(20)])
    expect(merged.map((point) => point.t)).toEqual([0, 10, 20])
  })

  test('no history keeps the live points; no live points keep the history', () => {
    expect(mergeHistory([], [live(1)]).length).toBe(1)
    expect(mergeHistory([live(1)], []).length).toBe(1)
  })

  test('never more than an hour', () => {
    const many = Array.from({ length: CHART_POINT_LIMIT }, (_, index) => live(index))
    expect(mergeHistory(many, [live(CHART_POINT_LIMIT + 5)]).length).toBe(CHART_POINT_LIMIT)
  })
})
