import { describe, expect, test } from 'bun:test'
import type { GpuLive } from './gpuLive.ts'
import { GPU_FLOOR_FALLBACK, gpuFloorText, gpuMemoryParts } from './gpuMemory.ts'

const GIB = 1024 ** 3
const card = (over: Partial<GpuLive> = {}): GpuLive => ({ name: 'RTX 5090', cards: 1, bookedGb: 0, totalGb: 32, usedGb: 29.5, freeGb: 2.5, ...over })

describe('gpuMemoryParts', () => {
  test('a card held by an outside program: in use, nothing booked, the rest free', () => {
    const parts = gpuMemoryParts(card())
    expect(parts).toMatchObject({ totalGb: 32, inUseGb: 29.5, bookedIdleGb: 0, freeGb: 2.5 })
  })

  test('the three parts always add up to the card', () => {
    for (const [booked, used] of [[0, 29.5], [8, 2], [4, 4], [0, 0]] as const) {
      const total = 32
      const parts = gpuMemoryParts(card({ bookedGb: booked, usedGb: used, freeGb: Math.round((total - Math.max(booked, used)) * 10) / 10 }))
      expect(parts).not.toBeNull()
      expect(Math.round(((parts?.inUseGb ?? 0) + (parts?.bookedIdleGb ?? 0) + (parts?.freeGb ?? 0)) * 10) / 10).toBe(total)
    }
  })

  test('promised and not taken yet is its own part', () => {
    expect(gpuMemoryParts(card({ bookedGb: 8, usedGb: 2, freeGb: 24 }))?.bookedIdleGb).toBe(6)
  })

  test('a card that has not reported, or no card, has no chart', () => {
    expect(gpuMemoryParts(null)).toBeNull()
    expect(gpuMemoryParts(card({ totalGb: null }))).toBeNull()
    expect(gpuMemoryParts(card({ usedGb: null }))).toBeNull()
    expect(gpuMemoryParts(card({ freeGb: null }))).toBeNull()
  })

  test('names the three biggest programs, biggest first', () => {
    const programs = [
      { name: 'a', memory_bytes: 1 * GIB },
      { name: 'sglang', memory_bytes: 28 * GIB },
      { name: 'b', memory_bytes: 3 * GIB },
      { name: 'c', memory_bytes: 2 * GIB },
    ]
    expect(gpuMemoryParts(card(), programs)?.programs.map((program) => program.name)).toEqual(['sglang', 'b', 'c'])
  })
})

describe('gpuFloorText', () => {
  test('says what the card really holds', () => {
    expect(gpuFloorText(gpuMemoryParts(card()))).toBe('RTX 5090 · 29.5 GB of 32 GB in use · 2.5 GB free')
  })

  test('keeps the old sentence while there is no reading', () => {
    expect(gpuFloorText(null)).toBe(GPU_FLOOR_FALLBACK)
  })
})
