import { expect, test } from 'bun:test'
import { LOSS_PERCENT, MAX_POINTS, SLOW_MS, latencyState, parseLatency, type Latency } from './latencyParse.ts'

const summary = (extra: Record<string, unknown> = {}) => ({ count: 360, failed: 2, average_ms: 12.5, max_ms: 40, last_ms: 11, percent_failed: 0.6, ...extra })
const answer = (extra: Record<string, unknown> = {}) => ({
  range: '1h', interval_seconds: 10, summary: summary(), points: [{ t: 1000, ms: 12 }, { t: 1010, ms: null }], ...extra,
})

test('a normal answer is read field by field, camelCase, with failed probes as null ms', () => {
  expect(parseLatency(answer())).toEqual({
    range: '1h',
    intervalSeconds: 10,
    summary: { count: 360, failed: 2, averageMs: 12.5, maxMs: 40, lastMs: 11, percentFailed: 0.6 },
    points: [{ t: 1000, ms: 12 }, { t: 1010, ms: null }],
  })
})

test('garbage input becomes empty safe values, never a made-up number', () => {
  const empty = { range: '', intervalSeconds: 0, summary: { count: 0, failed: 0, averageMs: null, maxMs: null, lastMs: null, percentFailed: 0 }, points: [] }
  for (const bad of [null, undefined, 'text', 42, [], true]) expect(parseLatency(bad), String(bad)).toEqual(empty)
})

test('wrong types and NaN in the fields fall back to safe defaults', () => {
  const odd = parseLatency(answer({
    range: 5,
    interval_seconds: 'ten',
    summary: summary({ count: '360', failed: NaN, average_ms: 'fast', max_ms: Infinity, last_ms: null, percent_failed: 'x' }),
    points: 'many',
  }))
  expect(odd.range).toBe('')
  expect(odd.intervalSeconds).toBe(0)
  expect(odd.summary).toEqual({ count: 0, failed: 0, averageMs: null, maxMs: null, lastMs: null, percentFailed: 0 })
  expect(odd.points).toEqual([])
})

test('a missing loss percentage is worked out from the counts; a reported one is kept between 0 and 100', () => {
  expect(parseLatency(answer({ summary: summary({ percent_failed: undefined, count: 200, failed: 10 }) })).summary.percentFailed).toBe(5)
  expect(parseLatency(answer({ summary: summary({ percent_failed: 250 }) })).summary.percentFailed).toBe(100)
  expect(parseLatency(answer({ summary: summary({ percent_failed: -3 }) })).summary.percentFailed).toBe(0)
})

test('failed probes cannot be more than the probes counted', () => {
  expect(parseLatency(answer({ summary: summary({ count: 3, failed: 9 }) })).summary.failed).toBe(3)
})

test('a point without a usable time is left out, and a negative or NaN ms becomes null', () => {
  const parsed = parseLatency(answer({ points: [{ t: 1, ms: -5 }, { t: 'x', ms: 3 }, { t: NaN, ms: 3 }, null, 'row', { t: 2, ms: NaN }, { t: 3, ms: 7 }] }))
  expect(parsed.points).toEqual([{ t: 1, ms: null }, { t: 2, ms: null }, { t: 3, ms: 7 }])
})

test('more than 1000 points are cut to 1000', () => {
  const many = Array.from({ length: MAX_POINTS + 250 }, (_, index) => ({ t: index, ms: 5 }))
  const parsed = parseLatency(answer({ points: many }))
  expect(parsed.points.length).toBe(MAX_POINTS)
  expect(parsed.points[MAX_POINTS - 1]).toEqual({ t: MAX_POINTS - 1, ms: 5 })
})

const withSummary = (extra: Partial<Latency['summary']>): Latency => ({
  range: '1h', intervalSeconds: 10, points: [], summary: { count: 10, failed: 0, averageMs: 10, maxMs: 10, lastMs: 10, percentFailed: 0, ...extra },
})

test('no probes at all is "none"', () => {
  expect(latencyState(withSummary({ count: 0, failed: 0, lastMs: null }))).toBe('none')
})

test('every probe failed is "down"', () => {
  expect(latencyState(withSummary({ count: 4, failed: 4, lastMs: null, percentFailed: 100 }))).toBe('down')
})

test('a last reading above the slow limit, or too much loss, is "slow"', () => {
  expect(latencyState(withSummary({ lastMs: SLOW_MS + 1 }))).toBe('slow')
  expect(latencyState(withSummary({ lastMs: SLOW_MS, percentFailed: 0 }))).toBe('ok')
  expect(latencyState(withSummary({ percentFailed: LOSS_PERCENT + 1 }))).toBe('slow')
  expect(latencyState(withSummary({ percentFailed: LOSS_PERCENT, lastMs: 10 }))).toBe('ok')
})

test('a fast machine with little loss is "ok", even when its last reading is missing', () => {
  expect(latencyState(withSummary({ lastMs: null, percentFailed: 1, failed: 1 }))).toBe('ok')
})
