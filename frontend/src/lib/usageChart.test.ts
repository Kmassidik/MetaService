import { expect, test } from 'bun:test'
import { CHART_HEIGHT, CHART_WIDTH, LABEL_ROOM, dayBars, dayLabel, officeTodayStart } from './usageChart.ts'
import type { UsageDay } from './usageParse.ts'

const day = (dayStart: number, inBytes: number, outBytes: number): UsageDay => ({ dayStart, inBytes, outBytes, inPeakBps: 0, outPeakBps: 0 })
const SATURDAY_OFFICE_MIDNIGHT = Date.UTC(2026, 10, 13, 17) / 1000

/** The item at an index; a missing one fails the test. */
function nth<T>(list: T[], index: number): T {
  const item = list[index]
  if (item === undefined) throw new Error(`no item at ${index}`)
  return item
}

test('the office day starts at midnight in UTC+7, so 03:00 UTC on 14 Nov is already 14 Nov there', () => {
  expect(officeTodayStart(Date.UTC(2026, 10, 14, 3))).toBe(SATURDAY_OFFICE_MIDNIGHT)
})

test('exactly at office midnight the day starts at that very moment, and just before it is the previous day', () => {
  expect(officeTodayStart(Date.UTC(2026, 10, 13, 17))).toBe(SATURDAY_OFFICE_MIDNIGHT)
  expect(officeTodayStart(Date.UTC(2026, 10, 13, 16, 59, 59))).toBe(SATURDAY_OFFICE_MIDNIGHT - 86_400)
})

test('a week shows short weekday names, a longer span shows the day of the month', () => {
  expect(dayLabel(SATURDAY_OFFICE_MIDNIGHT, 7)).toBe('Sat')
  expect(dayLabel(SATURDAY_OFFICE_MIDNIGHT, 30)).toBe('14')
})

test('bars are scaled so the biggest value reaches the top of the plot', () => {
  const plot = CHART_HEIGHT - LABEL_ROOM
  const bars = dayBars([day(1, 100, 50), day(2, 200, 0)])
  expect(nth(bars, 1).inHeight).toBe(plot)
  expect(nth(bars, 0).inHeight).toBe(plot / 2)
  expect(nth(bars, 0).outHeight).toBe(plot / 4)
  expect(nth(bars, 1).outHeight).toBe(0)
})

test('each bar keeps its day, and the upload bar sits right of the download bar', () => {
  const days = [day(1, 1, 1), day(2, 1, 1)]
  const bars = dayBars(days)
  expect(nth(bars, 1).day).toBe(nth(days, 1))
  expect(nth(bars, 1).x).toBeGreaterThan(nth(bars, 0).x + nth(bars, 0).width)
  expect(nth(bars, 0).outX).toBe(nth(bars, 0).x + nth(bars, 0).width)
  expect(nth(bars, 1).x + nth(bars, 1).width * 2).toBeLessThanOrEqual(CHART_WIDTH)
})

test('no traffic gives zero-height bars, and no days gives no bars', () => {
  expect(nth(dayBars([day(1, 0, 0)]), 0).inHeight).toBe(0)
  expect(dayBars([])).toEqual([])
})
