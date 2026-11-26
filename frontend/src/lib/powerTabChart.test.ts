import { describe, expect, test } from 'bun:test'
import { powerTabChart } from './powerTabChart.ts'
import { pointFromHistory, type LivePoint } from './liveSeries.ts'
import type { StatsHistoryPoint } from './types.ts'

const historyPoint = (t: number, extra: Partial<StatsHistoryPoint> = {}): StatsHistoryPoint => ({
  t, cpu_percent: 10, mem_used: 4, mem_cached: 2, mem_total: 8, swap_used: 0, swap_total: 0, net_in_bps: 100, net_out_bps: null, ...extra,
})

const point = (t: number, extra: Partial<LivePoint> = {}): LivePoint => ({ ...pointFromHistory(historyPoint(t)), ...extra })

describe('the Power tab chart', () => {
  test('one line per part the machine reports, named and coloured', () => {
    const chart = powerTabChart([point(0, { power: 120, cpuPower: 40, gpuPower: 60, anePower: 5 }), point(10, { power: 130, cpuPower: 45, gpuPower: 70, anePower: 3 })])
    expect(chart?.series.map((one) => one.key)).toEqual(['machine', 'cpu', 'gpu', 'ane'])
    expect(chart?.series.map((one) => one.name)).toEqual(['machine', 'CPU', 'GPU', 'ANE'])
    expect(chart?.series.map((one) => one.colour)).toEqual(['ink', 'blue', 'orange', 'teal'])
    expect(chart?.series.map((one) => one.dash)).toEqual(['solid', 'solid', 'dashed', 'dotted'])
    expect(chart?.series[2]?.values).toEqual([60, 70])
    expect(chart?.series[0]?.format(120)).toBe('120.0 W')
  })

  test('a part that never reported is left out, not a flat line of zeros', () => {
    const chart = powerTabChart([point(0, { power: 120 }), point(10, { power: 130 })])
    expect(chart?.series.map((one) => one.key)).toEqual(['machine'])
    expect(powerTabChart([point(0), point(10)])).toBeNull()
  })

  test('a gap in one line stays a gap while the others draw', () => {
    const chart = powerTabChart([point(0, { power: 120, cpuPower: 40 }), point(10), point(20, { power: 130, cpuPower: 45 })])
    expect(chart?.series[0]?.values).toEqual([120, null, 130])
    expect(chart?.series[1]?.values).toEqual([40, null, 45])
  })

  test('the axis fits what was seen, never below 10 watts, and its labels are whole watts', () => {
    expect(powerTabChart([point(0, { power: 5 })])?.ceiling).toBe(10)
    const hungry = powerTabChart([point(0, { cpuPower: 480 })])
    expect(hungry).not.toBeNull()
    if (hungry === null) return
    expect(hungry.ceiling).toBeGreaterThanOrEqual(480)
    expect(hungry.ticks[hungry.ticks.length - 1]).toBe(hungry.ceiling)
    expect(hungry.axisLabel(300)).toBe('300 W')
  })

  test('the split fields ride on the history points and live readings', () => {
    const history = pointFromHistory(historyPoint(0, { cpu_power_watts: 40.5, gpu_power_watts: 60, ane_power_watts: 2, cpu_core_voltage: 0.8, cpu_core_current: 3.2 }))
    expect(history).toMatchObject({ cpuPower: 40.5, gpuPower: 60, anePower: 2, coreVoltage: 0.8, coreCurrent: 3.2 })
  })
})
