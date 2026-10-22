// The optional parts of a GPU in a reading and in a history point. A helper that cannot read a number leaves it out, and a value of the wrong kind is treated as left out:
// they decorate the page, they must never break it, and an unreadable number is never turned into a 0.
import type { GpuVendor, StatsGpu, StatsGpuProgram, StatsHistoryGpu } from './types.ts'

type Rec = Record<string, unknown>

const VENDORS: readonly GpuVendor[] = ['nvidia', 'amd', 'apple', 'intel', 'unknown']
const MAX_PROGRAMS = 8

const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)
const finiteNumber = (value: unknown): number | undefined => (typeof value === 'number' && Number.isFinite(value) ? value : undefined)
const vendorOf = (value: unknown): GpuVendor | undefined => VENDORS.find((one) => one === value)

function programs(value: unknown): StatsGpuProgram[] | undefined {
  if (!Array.isArray(value)) return undefined
  return value.slice(0, MAX_PROGRAMS).flatMap((item): StatsGpuProgram[] => {
    const memory = isRec(item) ? finiteNumber(item.memory_bytes) : undefined
    return isRec(item) && typeof item.name === 'string' && memory !== undefined ? [{ name: item.name, memory_bytes: memory }] : []
  })
}

/** The optional parts of one GPU of a reading. */
export function gpuExtras(source: Rec): Pick<StatsGpu, 'vendor' | 'power_watts' | 'power_limit_watts' | 'fan_percent' | 'clock_mhz' | 'processes'> {
  const vendor = vendorOf(source.vendor)
  const power = finiteNumber(source.power_watts)
  const limit = finiteNumber(source.power_limit_watts)
  const fan = finiteNumber(source.fan_percent)
  const clock = finiteNumber(source.clock_mhz)
  const running = programs(source.processes)
  return {
    ...(vendor === undefined ? {} : { vendor }), ...(power === undefined ? {} : { power_watts: power }), ...(limit === undefined ? {} : { power_limit_watts: limit }),
    ...(fan === undefined ? {} : { fan_percent: fan }), ...(clock === undefined ? {} : { clock_mhz: clock }), ...(running === undefined ? {} : { processes: running }),
  }
}

/** The GPU series of a history point; entries of the wrong shape are skipped. */
export function historyGpus(value: unknown): StatsHistoryGpu[] | undefined {
  if (!Array.isArray(value)) return undefined
  const found = value.flatMap((item): StatsHistoryGpu[] => {
    const index = isRec(item) ? finiteNumber(item.index) : undefined
    if (!isRec(item) || index === undefined) return []
    const use = finiteNumber(item.utilization_percent)
    const memory = finiteNumber(item.memory_used_bytes)
    const temperature = finiteNumber(item.temperature_celsius)
    const power = finiteNumber(item.power_watts)
    return [{
      index, ...(use === undefined ? {} : { utilization_percent: use }), ...(memory === undefined ? {} : { memory_used_bytes: memory }),
      ...(temperature === undefined ? {} : { temperature_celsius: temperature }), ...(power === undefined ? {} : { power_watts: power }),
    }]
  })
  return found.length > 0 ? found : undefined
}
