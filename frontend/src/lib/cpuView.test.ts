import { describe, expect, test } from 'bun:test'
import { frequencyText, temperatureText, threadGroups, topologyLine } from './cpuView.ts'
import type { StatsCpu } from './types.ts'

const cpu = (extra: Partial<StatsCpu> = {}): StatsCpu => ({ core_count: 4, total_percent: 10, cores_percent: [10, 20, 30, 40], load: { one: 1, five: 1, fifteen: 1 }, ...extra })

describe('the topology line', () => {
  test('hyper-threading says cores and threads', () => {
    expect(topologyLine(cpu({ core_count: 32, physical_cores: 16 }))).toBe('16 cores · 32 threads')
  })

  test('no hyper-threading says cores only, and one core is singular', () => {
    expect(topologyLine(cpu({ core_count: 10, physical_cores: 10 }))).toBe('10 cores')
    expect(topologyLine(cpu({ core_count: 1, physical_cores: 1 }))).toBe('1 core')
  })

  test('named clusters say what the system says', () => {
    expect(topologyLine(cpu({ core_count: 10, physical_cores: 10, clusters: [{ name: 'Performance', logical: 4 }, { name: 'Efficiency', logical: 6 }] }))).toBe('4 performance + 6 efficiency')
  })

  test('an older helper that gives only the count says CPUs, not cores', () => {
    expect(topologyLine(cpu({ core_count: 8 }))).toBe('8 CPUs')
    expect(topologyLine(cpu({ core_count: 1 }))).toBe('1 CPU')
  })
})

describe('thread groups', () => {
  test('threads of one core sit together, cores in order, and the labels say core and thread', () => {
    const groups = threadGroups(cpu({ physical_cores: 2, core_of: [0, 1, 0, 1], cores_percent: [10, 20, 30, 40] }))
    expect(groups.map((group) => group.threads.map((thread) => thread.cpu))).toEqual([[0, 2], [1, 3]])
    expect(groups[0]?.threads.map((thread) => thread.label)).toEqual(['core 1 thread 1 · 10%', 'core 1 thread 2 · 30%'])
    expect(groups[1]?.threads[1]?.label).toBe('core 2 thread 2 · 40%')
    expect(groups.map((group) => group.core)).toEqual([1, 2])
  })

  test('without hyper-threading every core has one bar, labelled by core', () => {
    const groups = threadGroups(cpu({ physical_cores: 4, core_of: [0, 1, 2, 3] }))
    expect(groups.length).toBe(4)
    expect(groups[2]?.threads[0]?.label).toBe('core 3 · 30%')
  })

  test('an older helper has no grouping: every CPU alone, labelled CPU', () => {
    const groups = threadGroups(cpu())
    expect(groups.length).toBe(4)
    expect(groups[3]?.threads[0]?.label).toBe('CPU 4 · 40%')
  })

  test('a grouping of the wrong size is not believed', () => {
    expect(threadGroups(cpu({ physical_cores: 2, core_of: [0, 1] })).length).toBe(4)
  })

  test('core numbers that skip are still counted one after the other', () => {
    const groups = threadGroups(cpu({ core_count: 2, cores_percent: [5, 6], physical_cores: 2, core_of: [7, 3] }))
    expect(groups.map((group) => group.core)).toEqual([1, 2])
    expect(groups[0]?.threads[0]?.cpu).toBe(1)
  })

  test('still measuring: no bars', () => {
    expect(threadGroups(cpu({ cores_percent: null }))).toEqual([])
  })

  test('a thousand CPUs are grouped without trouble', () => {
    const many = Array.from({ length: 1024 }, (_, index) => index % 7)
    const groups = threadGroups(cpu({ core_count: 1024, physical_cores: 512, core_of: Array.from({ length: 1024 }, (_, index) => index % 512), cores_percent: many }))
    expect(groups.length).toBe(512)
    expect(groups[0]?.threads.length).toBe(2)
  })
})

describe('frequency and temperature', () => {
  test('are written plainly and say nothing when absent', () => {
    expect(frequencyText({ average: 4200, max: 4900 })).toBe('4.2 GHz (up to 4.9 GHz)')
    expect(frequencyText(undefined)).toBeNull()
    expect(temperatureText(61.6)).toBe('62 °C')
    expect(temperatureText(undefined)).toBeNull()
  })
})
