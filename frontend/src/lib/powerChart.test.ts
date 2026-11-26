import { describe, expect, test } from 'bun:test'
import { powerChart, powerText } from './powerChart.ts'
import { pointFromHistory, type LivePoint } from './liveSeries.ts'
import type { StatsHistoryPoint } from './types.ts'

const historyPoint = (t: number, extra: Partial<StatsHistoryPoint> = {}): StatsHistoryPoint => ({
  t, cpu_percent: 10, mem_used: 4, mem_cached: 2, mem_total: 8, swap_used: 0, swap_total: 0, net_in_bps: 100, net_out_bps: null, ...extra,
})

const point = (t: number, extra: Partial<LivePoint> = {}): LivePoint => ({ ...pointFromHistory(historyPoint(t)), ...extra })

describe('the power chart', () => {
  test('a machine that gave watts gets one line of them', () => {
    const chart = powerChart([point(0, { power: 102.3 }), point(10, { power: 110 })])
    expect(chart?.series.map((one) => one.name)).toEqual(['power'])
    expect(chart?.series[0]?.values).toEqual([102.3, 110])
    expect(chart?.series[0]?.format(102.3)).toBe('102.3 W')
  })

  test('a machine that never gave a watt has no chart, gaps in between are kept', () => {
    expect(powerChart([point(0), point(10)])).toBeNull()
    const gapped = powerChart([point(0, { power: 50 }), point(10), point(20, { power: 60 })])
    expect(gapped?.series[0]?.values).toEqual([50, null, 60])
  })

  test('the axis fits what was seen, never below 10 watts, and its labels are whole watts', () => {
    expect(powerChart([point(0, { power: 5 })])?.ceiling).toBe(10)
    const hungry = powerChart([point(0, { power: 480 })])
    expect(hungry).not.toBeNull()
    if (hungry === null) return
    expect(hungry.ceiling).toBeGreaterThanOrEqual(480)
    expect(hungry.ticks[hungry.ticks.length - 1]).toBe(hungry.ceiling)
    expect(hungry.axisLabel(300)).toBe('300 W')
  })
})

describe('the power text', () => {
  test('the newest reading wins and nothing read is a dash', () => {
    expect(powerText([point(0, { power: 50 }), point(10, { power: 102.3 })])).toBe('102.3 W')
    expect(powerText([point(0, { power: 50 }), point(10)])).toBe('50.0 W')
    expect(powerText([point(0), point(10)])).toBe('—')
    expect(powerText([])).toBe('—')
  })
})
