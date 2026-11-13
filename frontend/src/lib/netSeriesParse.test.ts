import { expect, test } from 'bun:test'
import { MAX_NET_POINTS, parseNetSeries, seriesFromHistory, withGaps, type NetSeriesPoint } from './netSeriesParse.ts'

const answer = (extra: Record<string, unknown> = {}) => ({
  range: '24h',
  bucket_seconds: 120,
  points: [{ t: 1000, in_bps: 500, out_bps: 80, in_peak_bps: 900, out_peak_bps: 120 }, { t: 1120, in_bps: 40, out_bps: 2, in_peak_bps: 60, out_peak_bps: 3 }],
  ...extra,
})

test('a normal answer is read field by field, camelCase, oldest first', () => {
  expect(parseNetSeries(answer())).toEqual({
    range: '24h',
    bucketSeconds: 120,
    points: [
      { t: 1000, inBps: 500, outBps: 80, inPeakBps: 900, outPeakBps: 120 },
      { t: 1120, inBps: 40, outBps: 2, inPeakBps: 60, outPeakBps: 3 },
    ],
  })
})

test('garbage input becomes an empty series, never a made-up number', () => {
  const empty = { range: '', bucketSeconds: 0, points: [] }
  for (const bad of [null, undefined, 'text', 42, [], true]) expect(parseNetSeries(bad), String(bad)).toEqual(empty)
})

test('negative, NaN, infinite and text speeds are gaps (null), and a bad bucket length is unknown', () => {
  const parsed = parseNetSeries(answer({
    bucket_seconds: -120,
    points: [{ t: 1, in_bps: -5, out_bps: NaN, in_peak_bps: Infinity, out_peak_bps: '9' }],
  }))
  expect(parsed.bucketSeconds).toBe(0)
  expect(parsed.points).toEqual([{ t: 1, inBps: null, outBps: null, inPeakBps: null, outPeakBps: null }])
})

test('a point without a usable time is left out, and a non-text range is empty', () => {
  const parsed = parseNetSeries(answer({ range: 7, points: [{ t: 'x', in_bps: 1 }, { t: NaN, in_bps: 1 }, null, 'row', { t: 3, in_bps: 7 }] }))
  expect(parsed.range).toBe('')
  expect(parsed.points).toEqual([{ t: 3, inBps: 7, outBps: null, inPeakBps: null, outPeakBps: null }])
})

test('control characters are removed from the range text', () => {
  expect(parseNetSeries(answer({ range: '24\u0007h\u0085' })).range).toBe('24h')
})

test('more than 1000 points keep the newest 1000', () => {
  const many = Array.from({ length: MAX_NET_POINTS + 250 }, (_, index) => ({ t: index * 120, in_bps: 1 }))
  const parsed = parseNetSeries(answer({ points: many }))
  expect(parsed.points.length).toBe(MAX_NET_POINTS)
  expect(parsed.points[0]?.t).toBe(250 * 120)
  expect(parsed.points[MAX_NET_POINTS - 1]?.t).toBe((MAX_NET_POINTS + 249) * 120)
})

test('the stats history becomes the same shape, with no peaks, and null speeds stay gaps', () => {
  expect(seriesFromHistory([{ t: 10, netIn: 100, netOut: null }, { t: NaN, netIn: 1, netOut: 1 }, { t: 20, netIn: -1, netOut: 4 }])).toEqual([
    { t: 10, inBps: 100, outBps: null, inPeakBps: null, outPeakBps: null },
    { t: 20, inBps: null, outBps: 4, inPeakBps: null, outPeakBps: null },
  ])
})

test('the history is capped at the newest 1000 points too', () => {
  const history = Array.from({ length: MAX_NET_POINTS + 5 }, (_, index) => ({ t: index, netIn: 1, netOut: 1 }))
  expect(seriesFromHistory(history).length).toBe(MAX_NET_POINTS)
})

test('a missing bucket becomes a gap: an empty point between points more than 1.5 buckets apart', () => {
  const at = (t: number): NetSeriesPoint => ({ t, inBps: 1, outBps: 1, inPeakBps: null, outPeakBps: null })
  const gapped = withGaps([at(0), at(120), at(600)], 120)
  expect(gapped.map((point) => point.t)).toEqual([0, 120, 240, 600])
  expect(gapped[2]).toEqual({ t: 240, inBps: null, outBps: null, inPeakBps: null, outPeakBps: null })
})

test('neighbouring buckets are not split, and an unknown bucket length adds no gaps', () => {
  const near = [{ t: 0, inBps: 1, outBps: 1, inPeakBps: null, outPeakBps: null }, { t: 120, inBps: 1, outBps: 1, inPeakBps: null, outPeakBps: null }]
  expect(withGaps(near, 120)).toEqual(near)
  expect(withGaps(near, 0)).toEqual(near)
})
