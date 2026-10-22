// The GPUs of the monitor stand-in: a machine has 0, 1 or 2 of them, of different makers. An NVIDIA card gives everything (and the programs on it), an AMD card what its driver shows,
// and an Apple GPU only use and memory (a Mac gives no temperature, power or clock without administrator rights). A number the maker cannot give is null or left out, never 0.
import type { Json } from '../support/json.ts'

const GIB = 1024 ** 3
const WAVE_SPAN = 70
const WAVE_FLOOR = 8
const MAC_MEMORY_TOTAL = 32 * GIB

export type GpuKind = 'nvidia' | 'amd' | 'apple'

const wave = (call: number, kindIndex: number, floor = WAVE_FLOOR, span = WAVE_SPAN) => Number((floor + (((call * 5 + kindIndex * 17) % span) + 0.5)).toFixed(1))

/** One GPU of a live reading. */
function gpuAt(call: number, kind: GpuKind, index: number): Json {
  const use = wave(call, index)
  if (kind === 'nvidia') {
    return {
      name: 'NVIDIA GeForce RTX 5090', vendor: 'nvidia', utilization_percent: use, memory_used_bytes: (4 + (call % 5)) * GIB, memory_total_bytes: 32 * GIB, temperature_celsius: 48 + (call % 20),
      power_watts: 120 + (call % 90) * 3, power_limit_watts: 575, fan_percent: 30 + (call % 30), clock_mhz: 1800 + (call % 6) * 100,
      processes: [{ name: 'python3', memory_bytes: 3 * GIB }, { name: 'llama-server', memory_bytes: GIB }],
    }
  }
  if (kind === 'amd') {
    return {
      name: 'AMD Radeon RX 7900 XTX', vendor: 'amd', utilization_percent: use, memory_used_bytes: (2 + (call % 4)) * GIB, memory_total_bytes: 24 * GIB, temperature_celsius: 44 + (call % 15),
      power_watts: 60 + (call % 60) * 2, power_limit_watts: 327, fan_percent: 25 + (call % 20), clock_mhz: 1200 + (call % 8) * 100,
    }
  }
  return { name: 'Apple M3 Max GPU', vendor: 'apple', utilization_percent: use, memory_used_bytes: (2 + (call % 6)) * GIB, memory_total_bytes: MAC_MEMORY_TOTAL, temperature_celsius: null }
}

export const gpusAt = (call: number, kinds: readonly GpuKind[]): Json[] => kinds.map((kind, index) => gpuAt(call, kind, index))

/** One GPU's numbers in a history point: only what the maker gives, and nothing for a number that is null. */
function seriesAt(call: number, kind: GpuKind, index: number): Json {
  const { utilization_percent: use, memory_used_bytes: memory, temperature_celsius: temperature, power_watts: power } = gpuAt(call, kind, index)
  return { index, utilization_percent: use, memory_used_bytes: memory, ...(typeof temperature === 'number' ? { temperature_celsius: temperature } : {}), ...(typeof power === 'number' ? { power_watts: power } : {}) }
}

/** The `gpus` of a history point; the key is left out for a machine without a GPU. */
export const gpuSeriesAt = (call: number, kinds: readonly GpuKind[]): Json => (kinds.length === 0 ? {} : { gpus: kinds.map((kind, index) => seriesAt(call, kind, index)) })
