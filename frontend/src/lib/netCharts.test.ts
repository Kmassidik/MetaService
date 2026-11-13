import { expect, test } from 'bun:test'
import { latencyChart, speedChart } from './chartSeries.ts'
import { formatDay, timeTicks } from './charts.ts'

test('the speed chart has a download and an upload line, and a gap stays a gap', () => {
  const chart = speedChart([{ t: 0, inBps: 1000, outBps: null }, { t: 10, inBps: null, outBps: 500 }])
  expect(chart.times).toEqual([0, 10])
  expect(chart.series.map((one) => one.name)).toEqual(['download', 'upload'])
  expect(chart.series[0]?.values).toEqual([1000, null])
  expect(chart.series[1]?.values).toEqual([null, 500])
  expect(chart.stacked).toBe(false)
})

test('the latency chart draws the milliseconds, and a failed probe is a gap with a mark', () => {
  const chart = latencyChart([{ t: 0, ms: 12 }, { t: 10, ms: null }, { t: 20, ms: 40 }])
  expect(chart.series[0]?.values).toEqual([12, null, 40])
  expect(chart.marks).toEqual([10])
  expect(chart.series[0]?.format(12.4)).toBe('12 ms')
  expect(chart.ticks[chart.ticks.length - 1]).toBeGreaterThanOrEqual(40)
})

test('a latency chart with no failed probe has no marks', () => {
  expect(latencyChart([{ t: 0, ms: 5 }]).marks).toEqual([])
})

test('a window of days labels the day, not the clock', () => {
  const ticks = timeTicks(0, 7 * 86_400, 5, 0)
  expect(ticks.length).toBeGreaterThanOrEqual(2)
  expect(ticks[0]).toEqual({ t: 0, label: '1 Jan' })
  expect(formatDay(86_400 * 31, 0)).toBe('1 Feb')
})
