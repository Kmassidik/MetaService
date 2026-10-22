import { describe, expect, test } from 'bun:test'
import { gpuInfos, gpuLineName, gpuMemoryChart, gpuPowerChart, gpuTemperatureChart, gpuUseChart, shortGpuName } from './gpuChart.ts'
import { gpuGauge, gaugeSpecs } from './gauges.ts'
import { appendPoint, pointFromHistory, pointFromReading, type LiveGpu, type LivePoint } from './liveSeries.ts'
import { parseHistoryReply } from './statsHistoryParse.ts'
import { parseStatsReply } from './statsParse.ts'
import type { MachineStats, StatsGpu } from './types.ts'

const GIB = 1024 ** 3

const gpuAt = (index: number, extra: Partial<LiveGpu> = {}): LiveGpu => ({ index, use: null, memory: null, temperature: null, power: null, ...extra })

const point = (t: number, gpus: LiveGpu[]): LivePoint => ({
  t, cpu: 10, breakdown: null, load: null, memUsed: 1, memCached: 1, memTotal: 10, swapUsed: 0, swapTotal: 0,
  diskRead: null, diskWrite: null, netIn: 1, netOut: 1, drops: null, processes: null, gpus,
})

const card = (extra: Partial<StatsGpu> = {}): StatsGpu => ({ name: 'NVIDIA GeForce RTX 5090', utilization_percent: 40, memory_used_bytes: 4 * GIB, memory_total_bytes: 32 * GIB, temperature_celsius: 55, ...extra })

describe('GPU line names', () => {
  test('the short name drops the maker and the word GPU and is cut when long', () => {
    expect(shortGpuName('NVIDIA GeForce RTX 5090')).toBe('RTX 5090')
    expect(shortGpuName('AMD Radeon RX 7900 XTX')).toBe('RX 7900 XTX')
    expect(shortGpuName('Apple M3 Max GPU')).toBe('M3 Max')
    expect(shortGpuName('GPU')).toBe('GPU')
    expect(shortGpuName('A very long graphics card name indeed')).toHaveLength(16)
  })

  test('several GPUs are told apart by number, one GPU is not numbered', () => {
    const [first] = gpuInfos([card()])
    expect(first && gpuLineName(first, true)).toBe('GPU 0 · RTX 5090')
    expect(first && gpuLineName(first, false)).toBe('GPU · RTX 5090')
  })
})

describe('the GPU charts', () => {
  const infos = gpuInfos([card(), card({ name: 'AMD Radeon RX 7900 XTX', memory_total_bytes: 24 * GIB })])
  const points = [
    point(0, [gpuAt(0, { use: 10, memory: GIB, temperature: 50, power: 200 }), gpuAt(1, { use: 30, memory: 2 * GIB })]),
    point(10, [gpuAt(0, { use: 20, memory: 2 * GIB, temperature: 52, power: 220 })]),
  ]

  test('one line per GPU, a missing reading is a gap and never 0', () => {
    const chart = gpuUseChart(points, infos)
    expect(chart?.series.map((one) => one.name)).toEqual(['GPU 0 · RTX 5090', 'GPU 1 · RX 7900 XTX'])
    expect(chart?.series[1]?.values).toEqual([30, null])
    expect(chart?.series[0]?.colour).not.toBe(chart?.series[1]?.colour)
    expect(chart?.stacked).toBe(false)
  })

  test('the memory axis ends at the biggest known total', () => {
    const chart = gpuMemoryChart(points, infos)
    expect(chart?.ceiling).toBe(32 * GIB)
    expect(chart?.ticks[0]).toBe(0)
  })

  test('without a known total the memory axis fits what was seen', () => {
    const unknown = gpuInfos([card({ memory_total_bytes: null })])
    const chart = gpuMemoryChart([point(0, [gpuAt(0, { memory: 3 * GIB })])], unknown)
    expect(chart && chart.ceiling >= 3 * GIB && chart.ceiling < 32 * GIB).toBe(true)
  })

  test('temperature and power are separate charts, each in its own unit', () => {
    const heat = gpuTemperatureChart(points, infos)
    const power = gpuPowerChart(points, infos)
    expect(heat?.series).toHaveLength(1)
    expect(heat?.axisLabel(60)).toBe('60 °C')
    expect(power?.axisLabel(200)).toBe('200 W')
  })

  test('a chart nobody has numbers for is not drawn', () => {
    const macOnly = [point(0, [gpuAt(0, { use: 5, memory: GIB })])]
    expect(gpuTemperatureChart(macOnly, infos)).toBeNull()
    expect(gpuPowerChart(macOnly, infos)).toBeNull()
    expect(gpuUseChart([point(0, [])], infos)).toBeNull()
  })
})

describe('GPU numbers in the points', () => {
  const stats = (gpus: StatsGpu[]): MachineStats => ({
    taken_at: 't', measuring: false, uptime_seconds: 1, gpus, processes: [],
    cpu: { core_count: 2, total_percent: 5, cores_percent: null, load: { one: 1, five: 1, fifteen: 1 } },
    memory: { total_bytes: 10, used_bytes: 1, cached_bytes: 1, free_bytes: 8, swap_total_bytes: 0, swap_used_bytes: 0 }, disks: [],
    network: { received_total_bytes: 1, sent_total_bytes: 1, received_bytes_per_second: 1, sent_bytes_per_second: 1 },
  })
  const reply = (gpus: StatsGpu[]) => ({ state: 'online' as const, last_seen: null, fetched_at: '2026-10-22T10:00:00Z', stats: stats(gpus) })

  test('a live reading keeps the GPUs that gave a number, by index', () => {
    const silent = card({ utilization_percent: null, memory_used_bytes: null, memory_total_bytes: null, temperature_celsius: null })
    const made = pointFromReading(reply([silent, card({ power_watts: 300 })]), 0)
    expect(made?.gpus).toEqual([{ index: 1, use: 40, memory: 4 * GIB, temperature: 55, power: 300 }])
  })

  test('a machine without a GPU has no GPU numbers', () => {
    expect(pointFromReading(reply([]), 0)?.gpus).toEqual([])
  })

  test('a history point turns the series into live numbers and absent ones into nulls', () => {
    const parsed = parseHistoryReply({ interval_seconds: 10, points: [{ t: 1, cpu_percent: 1, mem_used: 1, mem_cached: 1, mem_total: 2, swap_used: 0, swap_total: 0, net_in_bps: null, net_out_bps: null,
      gpus: [{ index: 2, utilization_percent: 7 }, { index: 'x' }, 'junk'] }] })
    expect(parsed.points[0] && pointFromHistory(parsed.points[0]).gpus).toEqual([{ index: 2, use: 7, memory: null, temperature: null, power: null }])
  })

  test('a history point without gpus parses with none', () => {
    const parsed = parseHistoryReply({ interval_seconds: 10, points: [{ t: 1, cpu_percent: 1, mem_used: 1, mem_cached: 1, mem_total: 2, swap_used: 0, swap_total: 0, net_in_bps: null, net_out_bps: null }] })
    expect(parsed.points[0]?.gpus).toBeUndefined()
    expect(appendPoint([], point(1, []))).toHaveLength(1)
  })

  test('the new optional GPU fields are read, with a bad vendor and bad numbers left out', () => {
    const base = { taken_at: 't', measuring: false, uptime_seconds: 1, processes: [], disks: [],
      cpu: { core_count: 2, total_percent: 5, cores_percent: null, load: { one: 1, five: 1, fifteen: 1 } },
      memory: { total_bytes: 10, used_bytes: 1, cached_bytes: 1, free_bytes: 8, swap_total_bytes: 0, swap_used_bytes: 0 },
      network: { received_total_bytes: 1, sent_total_bytes: 1, received_bytes_per_second: 1, sent_bytes_per_second: 1 } }
    const gpu = { name: 'g', utilization_percent: 1, memory_used_bytes: 1, memory_total_bytes: 2, temperature_celsius: 3 }
    const parsed = parseStatsReply({ state: 'online', last_seen: null, fetched_at: null, stats: { ...base, gpus: [
      { ...gpu, vendor: 'nvidia', power_watts: 5, fan_percent: 'fast', clock_mhz: 900, processes: [{ name: 'a', memory_bytes: 1 }, { name: 2 }] },
      { ...gpu, vendor: '<script>' },
    ] } })
    const [first, second] = parsed.stats?.gpus ?? []
    expect([first?.vendor, first?.power_watts, first?.fan_percent, first?.clock_mhz]).toEqual(['nvidia', 5, undefined, 900])
    expect(first?.processes).toEqual([{ name: 'a', memory_bytes: 1 }])
    expect(second?.vendor).toBeUndefined()
  })
})

describe('the GPU gauge', () => {
  const stats = (gpus: StatsGpu[]) => ({ cpu: { core_count: 2, total_percent: 5, cores_percent: null, load: { one: 1, five: 1, fifteen: 1 } },
    memory: { total_bytes: 10, used_bytes: 1, cached_bytes: 1, free_bytes: 8, swap_total_bytes: 0, swap_used_bytes: 0 }, disks: [], gpus }) as unknown as MachineStats

  test('shows the busiest GPU', () => {
    const gauge = gpuGauge(stats([card({ utilization_percent: 20 }), card({ utilization_percent: 80 })]))
    expect([gauge?.percent, gauge?.caption]).toEqual([80, 'busiest of 2 GPUs'])
  })

  test('is left out without a GPU or when no GPU says how busy it is', () => {
    expect(gaugeSpecs(stats([])).map((one) => one.key)).not.toContain('gpu')
    expect(gpuGauge(stats([card({ utilization_percent: null })]))).toBeNull()
  })

  test('is the sixth gauge when there is one', () => {
    expect(gaugeSpecs(stats([card()])).map((one) => one.key)).toEqual(['cpu', 'memory', 'load', 'swap', 'disk', 'gpu'])
  })
})
