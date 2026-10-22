import { describe, expect, test } from 'bun:test'
import {
  areaPaths, bucketMeans, gaugeArc, gaugeLevel, linePath, linearScale, nearestIndex, niceBytesTicks, niceTicks, scalePoints, stackSeries, timeTicks, formatClock, formatClockSeconds, plotArea, type Pt,
} from './charts.ts'

describe('linearScale', () => {
  test('maps the domain onto the range, also backwards (a y axis grows upwards)', () => {
    const x = linearScale(0, 10, 100, 200)
    expect(x(0)).toBe(100)
    expect(x(10)).toBe(200)
    expect(x(5)).toBe(150)
    const y = linearScale(0, 100, 50, 0)
    expect(y(0)).toBe(50)
    expect(y(100)).toBe(0)
  })

  test('an empty domain maps everything to the start of the range instead of dividing by zero', () => {
    expect(linearScale(5, 5, 10, 20)(5)).toBe(10)
  })
})

describe('niceTicks', () => {
  test('rounds up to 1, 2 or 5 times a power of ten and starts at zero', () => {
    expect(niceTicks(87, 4)).toEqual([0, 25, 50, 75, 100])
    expect(niceTicks(100, 4)).toEqual([0, 25, 50, 75, 100])
    expect(niceTicks(0.35, 4)).toEqual([0, 0.1, 0.2, 0.3, 0.4])
    expect(niceTicks(12, 4)).toEqual([0, 5, 10, 15])
  })

  test('nothing to draw still gives a small scale, never an empty one', () => {
    expect(niceTicks(0, 4)).toEqual([0, 1])
    expect(niceTicks(Number.NaN, 4)).toEqual([0, 1])
    expect(niceTicks(-3, 4)).toEqual([0, 1])
  })

  test('the last tick is never below the largest value', () => {
    for (const max of [1, 3.3, 7, 19, 99, 101, 4096, 123456]) {
      const ticks = niceTicks(max, 4)
      expect(ticks[ticks.length - 1] ?? 0).toBeGreaterThanOrEqual(max)
    }
  })
})

describe('niceBytesTicks', () => {
  test('steps in whole units of 1024, so the labels read 0, 0.5, 1 MB and not 524288', () => {
    const { ticks, unit } = niceBytesTicks(900 * 1024, 4)
    expect(unit).toBe(1024)
    expect(ticks.map((tick) => tick / unit)).toEqual([0, 250, 500, 750, 1000])
  })

  test('uses the unit of the largest value', () => {
    expect(niceBytesTicks(3 * 1024 ** 3, 4).unit).toBe(1024 ** 3)
    expect(niceBytesTicks(500, 4).unit).toBe(1)
  })

  test('a quiet line still has a scale', () => {
    expect(niceBytesTicks(0, 4).ticks).toEqual([0, 1])
  })
})

describe('line and area paths', () => {
  const pts = (list: (number | null)[]): (Pt | null)[] => list.map((value, index) => (value === null ? null : { x: index * 10, y: value }))

  test('a line is one run; a missing value breaks it into two', () => {
    expect(linePath(pts([1, 2, 3]))).toBe('M0 1L10 2L20 3')
    expect(linePath(pts([1, null, 3, 4]))).toBe('M0 1M20 3L30 4')
  })

  test('nothing to draw is an empty path', () => {
    expect(linePath([])).toBe('')
    expect(linePath(pts([null, null]))).toBe('')
  })

  test('scalePoints applies both scales and keeps the gaps', () => {
    const result = scalePoints([0, 10, 20], [5, null, 15], linearScale(0, 20, 0, 200), linearScale(0, 20, 100, 0))
    expect(result).toEqual([{ x: 0, y: 75 }, null, { x: 200, y: 25 }])
  })

  test('an area is the top edge left to right, then the bottom edge back, closed; one per run', () => {
    const upper = pts([5, 6, null, 7, 8])
    const lower = pts([0, 0, null, 0, 0])
    const shapes = areaPaths(upper, lower)
    expect(shapes).toEqual(['M0 5L10 6L10 0L0 0Z', 'M30 7L40 8L40 0L30 0Z'])
  })

  test('a single point has no area', () => {
    expect(areaPaths(pts([5, null, 6]), pts([0, null, 0]))).toEqual([])
  })
})

describe('stackSeries', () => {
  test('each layer sits on the ones below it', () => {
    const layers = stackSeries([[1, 2], [3, 4], [5, 6]])
    expect(layers.map((layer) => layer.lower)).toEqual([[0, 0], [1, 2], [4, 6]])
    expect(layers.map((layer) => layer.upper)).toEqual([[1, 2], [4, 6], [9, 12]])
  })

  test('a missing value is a gap in its own layer and adds nothing to the ones above', () => {
    const layers = stackSeries([[1, null], [3, 4]])
    expect(layers[0]?.upper).toEqual([1, null])
    expect(layers[1]?.lower).toEqual([1, 0])
    expect(layers[1]?.upper).toEqual([4, 4])
  })

  test('nothing in gives nothing out', () => {
    expect(stackSeries([])).toEqual([])
  })
})

describe('gaugeArc', () => {
  test('0 percent draws an empty value arc and the track runs the whole half circle', () => {
    const arc = gaugeArc(0, 50)
    expect(arc.track).toBe('M0 50A50 50 0 0 1 100 50')
    expect(arc.value).toBe('')
  })

  test('50 percent ends straight up, 100 percent ends at the right', () => {
    expect(gaugeArc(50, 50).value).toBe('M0 50A50 50 0 0 1 50 0')
    expect(gaugeArc(100, 50).value).toBe('M0 50A50 50 0 0 1 100 50')
  })

  test('a reading that is not there yet, or past the ends, is held inside 0..100', () => {
    expect(gaugeArc(null, 50).value).toBe('')
    expect(gaugeArc(250, 50).value).toBe(gaugeArc(100, 50).value)
    expect(gaugeArc(-4, 50).value).toBe('')
    expect(gaugeArc(Number.NaN, 50).value).toBe('')
  })
})

describe('gaugeLevel', () => {
  test('normal below 75, high from 75, critical from 90; nothing yet is normal', () => {
    expect(gaugeLevel(null)).toBe('normal')
    expect(gaugeLevel(74.9)).toBe('normal')
    expect(gaugeLevel(75)).toBe('high')
    expect(gaugeLevel(89.9)).toBe('high')
    expect(gaugeLevel(90)).toBe('critical')
    expect(gaugeLevel(100)).toBe('critical')
  })
})

describe('bucketMeans', () => {
  test('a short series is left alone', () => {
    expect(bucketMeans([1, 2, 3], 10)).toEqual([1, 2, 3])
  })

  test('a long series is averaged into the wanted number of buckets, gaps ignored', () => {
    expect(bucketMeans([1, 3, 5, 7], 2)).toEqual([2, 6])
    expect(bucketMeans([1, null, null, null, 4, 6], 3)).toEqual([1, null, 5])
  })

  test('the buckets cover every value once', () => {
    const out = bucketMeans(Array.from({ length: 360 }, (_, index) => index), 100)
    expect(out.length).toBe(100)
  })
})

describe('time axis', () => {
  test('clock labels are HH:MM in the given zone', () => {
    expect(formatClock(0, 0)).toBe('00:00')
    expect(formatClock(3600 * 13 + 60 * 5, 0)).toBe('13:05')
    expect(formatClock(3600 * 13 + 60 * 5, -60)).toBe('14:05')
  })

  test('a pointed-at time also shows seconds', () => {
    expect(formatClockSeconds(3600 * 13 + 60 * 5 + 7, 0)).toBe('13:05:07')
    expect(formatClockSeconds(59, 0)).toBe('00:00:59')
  })

  test('ticks fall on round minutes, inside the range, with a sensible step', () => {
    const ticks = timeTicks(0, 3600, 6, 0)
    expect(ticks.length).toBeGreaterThanOrEqual(4)
    expect(ticks.length).toBeLessThanOrEqual(7)
    expect(ticks.every((tick) => tick.t >= 0 && tick.t <= 3600 && tick.t % 600 === 0)).toBe(true)
    expect(ticks[0]).toEqual({ t: 0, label: '00:00' })
  })

  test('a short range gets a short step, an empty or backwards range gets none', () => {
    const short = timeTicks(1000, 1300, 6, 0)
    expect(short.every((tick) => tick.t % 60 === 0)).toBe(true)
    expect(timeTicks(10, 10, 6, 0)).toEqual([])
    expect(timeTicks(20, 10, 6, 0)).toEqual([])
  })
})

describe('nearestIndex', () => {
  const times = [0, 10, 20, 30]
  test('picks the closest time', () => {
    expect(nearestIndex(times, 4)).toBe(0)
    expect(nearestIndex(times, 6)).toBe(1)
    expect(nearestIndex(times, 29)).toBe(3)
    expect(nearestIndex(times, 999)).toBe(3)
    expect(nearestIndex(times, -50)).toBe(0)
  })

  test('nothing to pick from is -1', () => {
    expect(nearestIndex([], 5)).toBe(-1)
  })
})

describe('plotArea', () => {
  test('leaves room on the left for the widest y label and below for the time labels', () => {
    const narrow = plotArea(400, 200, ['0', '50%'])
    const wide = plotArea(400, 200, ['0', '100 MB/s'])
    expect(wide.left).toBeGreaterThan(narrow.left)
    expect(narrow.height).toBeLessThan(200)
    expect(narrow.left + narrow.width).toBeLessThanOrEqual(400)
  })

  test('a tiny chart still has a plot to draw in', () => {
    const tiny = plotArea(50, 20, ['1000 MB/s'])
    expect(tiny.width).toBeGreaterThanOrEqual(60)
    expect(tiny.height).toBeGreaterThanOrEqual(1)
  })

  test('no labels at all is fine', () => {
    expect(plotArea(300, 150, []).left).toBeGreaterThan(0)
  })
})
