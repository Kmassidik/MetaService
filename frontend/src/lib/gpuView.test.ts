import { describe, expect, test } from 'bun:test'
import { gpuFacts, memoryText, showsMacNote, vendorLabel } from './gpuView.ts'
import type { StatsGpu } from './types.ts'

const GIB = 1024 ** 3
const base: StatsGpu = { name: 'g', utilization_percent: null, memory_used_bytes: null, memory_total_bytes: null, temperature_celsius: null }

describe('the GPU card words', () => {
  test('lists only what was readable, in a fixed order, with the power limit', () => {
    const facts = gpuFacts({ ...base, temperature_celsius: 61.4, power_watts: 215.2, power_limit_watts: 327, fan_percent: 50.2, clock_mhz: 1800 })
    expect(facts.map((fact) => `${fact.label} ${fact.value}`)).toEqual(['Temperature 61 °C', 'Power 215 W of 327 W', 'Fan 50%', 'Clock 1800 MHz'])
  })

  test('an Intel or Mac GPU shows no zeros for what it cannot read', () => {
    expect(gpuFacts(base)).toEqual([])
    expect(gpuFacts({ ...base, clock_mhz: 650 }).map((fact) => fact.key)).toEqual(['clock'])
    expect(gpuFacts({ ...base, power_limit_watts: 100 })[0]?.value).toBe('limit 100 W')
  })

  test('memory is "used of total", or just used, or nothing', () => {
    expect(memoryText({ ...base, memory_used_bytes: 2 * GIB, memory_total_bytes: 32 * GIB })).toBe('2 GB of 32 GB')
    expect(memoryText({ ...base, memory_used_bytes: 2 * GIB })).toBe('2 GB')
    expect(memoryText(base)).toBeNull()
  })

  test('the maker chip and the Mac note', () => {
    expect(vendorLabel({ ...base, vendor: 'amd' })).toBe('AMD')
    expect(vendorLabel(base)).toBe('GPU')
    expect(showsMacNote([{ ...base, vendor: 'apple' }])).toBe(true)
    expect(showsMacNote([{ ...base, vendor: 'nvidia' }])).toBe(false)
  })
})
