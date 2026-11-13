import { expect, test } from 'bun:test'
import { SPARK_WIDTH, sparkline } from './latencySpark.ts'

test('answered probes make one line, and a failed probe breaks it and is a tick', () => {
  const shape = sparkline([{ t: 1, ms: 10 }, { t: 2, ms: 10 }, { t: 3, ms: null }, { t: 4, ms: 5 }, { t: 5, ms: 5 }])
  expect(shape.lines.length).toBe(2)
  expect(shape.failedX).toEqual([SPARK_WIDTH / 2])
})

test('a failed probe at the very start or end leaves no empty line', () => {
  const shape = sparkline([{ t: 1, ms: null }, { t: 2, ms: 3 }, { t: 3, ms: 3 }, { t: 4, ms: null }])
  expect(shape.lines.length).toBe(1)
  expect(shape.failedX.length).toBe(2)
})

test('no points give nothing to draw, and one point gives a single centred position', () => {
  expect(sparkline([])).toEqual({ lines: [], failedX: [] })
  expect(sparkline([{ t: 1, ms: 4 }]).lines.length).toBe(1)
})

test('all failed points draw no line, only ticks', () => {
  const shape = sparkline([{ t: 1, ms: null }, { t: 2, ms: null }])
  expect(shape.lines).toEqual([])
  expect(shape.failedX.length).toBe(2)
})
