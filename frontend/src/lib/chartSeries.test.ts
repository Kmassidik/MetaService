import { describe, expect, test } from 'bun:test'
import { cpuChart, diskChart, loadChart, memoryChart, networkChart } from './chartSeries.ts'
import type { LivePoint } from './liveSeries.ts'

const point = (t: number, extra: Partial<LivePoint> = {}): LivePoint => ({
  t, cpu: 10, breakdown: null, load: null, memUsed: 400, memCached: 200, memTotal: 1000, swapUsed: 0, swapTotal: 0,
  diskRead: null, diskWrite: null, netIn: 100, netOut: 50, drops: null, processes: null, gpus: [], ...extra,
})

describe('the CPU chart', () => {
  test('a Linux helper gives the states that appear, bottom to top, and never idle', () => {
    const linux = { user: 10, system: 5, nice: 0, idle: 80, iowait: 3, irq: 1, softirq: 1, steal: 0 }
    const chart = cpuChart([point(0, { breakdown: linux }), point(10, { breakdown: linux })])
    expect(chart.series.map((one) => one.name)).toEqual(['user', 'system', 'nice', 'irq', 'softirq', 'iowait', 'steal'])
    expect(chart.stacked).toBe(true)
  })

  test('a Mac gives user, system and nice only', () => {
    const mac = { user: 10, system: 5, nice: 0, idle: 85 }
    expect(cpuChart([point(0, { breakdown: mac })]).series.map((one) => one.name)).toEqual(['user', 'system', 'nice'])
  })

  test('an older helper with no breakdown gets one series: the total in use', () => {
    const chart = cpuChart([point(0), point(10)])
    expect(chart.series.map((one) => one.name)).toEqual(['in use'])
    expect(chart.series[0]?.values).toEqual([10, 10])
  })

  test('the axis fits what was seen, never below 10 percent, and its last tick is at the top', () => {
    const quiet = cpuChart([point(0, { breakdown: { user: 2, system: 1 } })])
    expect(quiet.ceiling).toBe(10)
    const busy = cpuChart([point(0, { breakdown: { user: 70, system: 20 } })])
    expect(busy.ceiling).toBeGreaterThanOrEqual(90)
    expect(busy.ticks[busy.ticks.length - 1]).toBe(busy.ceiling)
    expect(busy.axisLabel(50)).toBe('50%')
  })

  test('the legend shows percents with one decimal', () => {
    expect(cpuChart([point(0)]).series[0]?.format(12.34)).toBe('12.3%')
  })
})

describe('the load chart', () => {
  test('has the 1, 5 and 15 minute lines, told apart by colour and by pattern', () => {
    const chart = loadChart([point(0, { load: [1, 2, 3] })])
    expect(chart.series.map((one) => one.name)).toEqual(['1m', '5m', '15m'])
    expect(new Set(chart.series.map((one) => one.dash)).size).toBe(3)
    expect(new Set(chart.series.map((one) => one.colour)).size).toBe(3)
    expect(chart.stacked).toBe(false)
    expect(chart.ceiling).toBeGreaterThanOrEqual(3)
  })

  test('a point without load is a gap', () => {
    expect(loadChart([point(0), point(10, { load: [1, 1, 1] })]).series[0]?.values).toEqual([null, 1])
  })
})

describe('the memory chart', () => {
  test('stacks used and cached up to the total, and lists free without drawing it', () => {
    const chart = memoryChart([point(0)])
    expect(chart.series.map((one) => [one.name, one.drawn])).toEqual([['used', true], ['cached', true], ['free', false]])
    expect(chart.series[2]?.values).toEqual([400])
    expect(chart.ceiling).toBeGreaterThanOrEqual(1000)
  })

  test('free never goes below zero', () => {
    expect(memoryChart([point(0, { memUsed: 900, memCached: 300 })]).series[2]?.values).toEqual([0])
  })
})

describe('disk and network', () => {
  test('without any disk speed there is no disk chart, so the card can say so', () => {
    expect(diskChart([point(0), point(10)])).toBeNull()
  })

  test('with a disk speed there are two lines, reads and writes', () => {
    const chart = diskChart([point(0, { diskRead: 1000, diskWrite: 10 })])
    expect(chart?.series.map((one) => one.name)).toEqual(['reads', 'writes'])
    expect(chart?.series[0]?.format(2048)).toBe('2 KB/s')
  })

  test('the network axis fits the biggest speed, in whole units, and a quiet line still has a scale', () => {
    const fast = networkChart([point(0, { netIn: 5 * 1024 ** 2 })])
    expect(fast.ceiling).toBeGreaterThanOrEqual(5 * 1024 ** 2)
    expect(fast.axisLabel(fast.ticks[1] ?? 0)).toMatch(/MB\/s$/)
    const quiet = networkChart([point(0, { netIn: 1, netOut: 1 })])
    expect(quiet.ceiling).toBeGreaterThanOrEqual(10 * 1024)
    expect(quiet.series.map((one) => one.name)).toEqual(['in', 'out'])
  })

  test('an unknown speed is a gap, not 0', () => {
    expect(networkChart([point(0, { netIn: null })]).series[0]?.values).toEqual([null])
  })
})
