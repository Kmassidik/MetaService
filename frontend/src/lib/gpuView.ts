// The words of the GPU card: the maker chip, the detail lines that were readable, and the note for a Mac. Pure functions, no DOM.
// A number the machine could not read is not listed at all: no "0 W", no "0 °C".
import { formatBytes } from './stats.ts'
import type { GpuVendor, StatsGpu } from './types.ts'

export const VENDOR_LABEL: Record<GpuVendor, string> = { nvidia: 'NVIDIA', amd: 'AMD', apple: 'Apple', intel: 'Intel', unknown: 'GPU' }

export const MAC_NOTE = "On a Mac the GPU shares the computer's memory; temperature and power need administrator rights, so they are not shown."
export const NO_PROGRAMS_TEXT = 'No program is using the GPU right now.'

export interface GpuFact { key: string; label: string; value: string }

export const vendorLabel = (gpu: StatsGpu): string => VENDOR_LABEL[gpu.vendor ?? 'unknown']

const wholeWatts = (watts: number): string => `${Math.round(watts)} W`

function powerText(gpu: StatsGpu): string | null {
  if (gpu.power_watts !== undefined) return gpu.power_limit_watts === undefined ? wholeWatts(gpu.power_watts) : `${wholeWatts(gpu.power_watts)} of ${wholeWatts(gpu.power_limit_watts)}`
  return gpu.power_limit_watts === undefined ? null : `limit ${wholeWatts(gpu.power_limit_watts)}`
}

/** The small facts that were readable, in a fixed order: temperature, power, fan, clock. */
export function gpuFacts(gpu: StatsGpu): GpuFact[] {
  const power = powerText(gpu)
  const facts: (GpuFact | null)[] = [
    gpu.temperature_celsius === null ? null : { key: 'temperature', label: 'Temperature', value: `${Math.round(gpu.temperature_celsius)} °C` },
    power === null ? null : { key: 'power', label: 'Power', value: power },
    gpu.fan_percent === undefined ? null : { key: 'fan', label: 'Fan', value: `${Math.round(gpu.fan_percent)}%` },
    gpu.clock_mhz === undefined ? null : { key: 'clock', label: 'Clock', value: `${Math.round(gpu.clock_mhz)} MHz` },
  ]
  return facts.filter((fact): fact is GpuFact => fact !== null)
}

/** "2.1 GB of 32 GB", or just the used part when the total is not known. Null when the used part is not known. */
export function memoryText(gpu: StatsGpu): string | null {
  if (gpu.memory_used_bytes === null) return null
  return gpu.memory_total_bytes === null ? formatBytes(gpu.memory_used_bytes) : `${formatBytes(gpu.memory_used_bytes)} of ${formatBytes(gpu.memory_total_bytes)}`
}

export const showsMacNote = (gpus: readonly StatsGpu[]): boolean => gpus.some((gpu) => gpu.vendor === 'apple')
