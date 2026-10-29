// The GPU memory chart and the Building's GPU floor: how much of the card is in use right now, how much is booked and not used yet, and how much is free.
// "In use" is the card's real reading, whoever holds it. Free is taken from the larger of booked and in use (see gpuLive.ts), so the three add up to the card. Pure, no DOM.
import { gbText, type GpuLive } from './gpuLive.ts'
import type { StatsGpuProgram } from './types.ts'

const BYTES_PER_GIB = 1024 ** 3
const TENTHS = 10
/** The chart names this many programs; the Live tab lists all of them. */
const PROGRAMS_SHOWN = 3
export const GPU_FLOOR_FALLBACK = 'GPU · not used by VMs yet'

export interface GpuProgramUse {
  name: string
  gb: number
}

export interface GpuMemoryParts {
  name: string
  totalGb: number
  inUseGb: number
  /** Promised to VMs and not taken yet. */
  bookedIdleGb: number
  freeGb: number
  programs: GpuProgramUse[]
}

const tenths = (gb: number): number => Math.round(gb * TENTHS) / TENTHS

/** The biggest holders of the card's memory, biggest first. */
function biggest(programs: readonly StatsGpuProgram[]): GpuProgramUse[] {
  return programs
    .map((program) => ({ name: program.name, gb: tenths(program.memory_bytes / BYTES_PER_GIB) }))
    .sort((a, b) => b.gb - a.gb)
    .slice(0, PROGRAMS_SHOWN)
}

/** The chart's numbers, or null while the card has not reported all of them (a Mac, an old helper, a machine that is off). */
export function gpuMemoryParts(gpu: GpuLive | null, programs: readonly StatsGpuProgram[] = []): GpuMemoryParts | null {
  if (gpu === null || gpu.totalGb === null || gpu.usedGb === null || gpu.freeGb === null) return null
  return {
    name: gpu.name,
    totalGb: gpu.totalGb,
    inUseGb: gpu.usedGb,
    bookedIdleGb: tenths(Math.max(0, gpu.bookedGb - gpu.usedGb)),
    freeGb: gpu.freeGb,
    programs: biggest(programs),
  }
}

/** The GPU floor of the Building: the card's real use, not the old "not used by VMs yet" while a program holds the card. */
export function gpuFloorText(parts: GpuMemoryParts | null): string {
  if (parts === null) return GPU_FLOOR_FALLBACK
  return `${parts.name} · ${gbText(parts.inUseGb)} of ${gbText(parts.totalGb)} in use · ${gbText(parts.freeGb)} free`
}
