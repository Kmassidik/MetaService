// The optional numbers of a stats reading (cores and threads, CPU states, disk speed, drops, frequency, temperature, thread counts).
// A helper that does not know them leaves them out, and a value of the wrong kind is treated as left out: they decorate the page, they must never break it.
import type { MachineStats, StatsBreakdown, StatsCluster, StatsCpu, StatsNetwork, StatsProcess } from './types.ts'

type Rec = Record<string, unknown>

const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)
const finiteNumber = (value: unknown): number | undefined => (typeof value === 'number' && Number.isFinite(value) ? value : undefined)

const BREAKDOWN_KEYS: readonly (keyof StatsBreakdown)[] = ['user', 'system', 'nice', 'idle', 'iowait', 'irq', 'softirq', 'steal']

function numberList(value: unknown): number[] | undefined {
  if (!Array.isArray(value)) return undefined
  const numbers = value.map(finiteNumber)
  return numbers.every((item): item is number => item !== undefined) ? numbers : undefined
}

function clusters(value: unknown): StatsCluster[] | undefined {
  if (!Array.isArray(value)) return undefined
  const found = value.flatMap((item): StatsCluster[] => {
    const logical = isRec(item) ? finiteNumber(item.logical) : undefined
    return isRec(item) && typeof item.name === 'string' && logical !== undefined ? [{ name: item.name, logical }] : []
  })
  return found.length > 0 ? found : undefined
}

export function breakdown(value: unknown): StatsBreakdown | undefined {
  if (!isRec(value)) return undefined
  const user = finiteNumber(value.user)
  const system = finiteNumber(value.system)
  const nice = finiteNumber(value.nice)
  const idle = finiteNumber(value.idle)
  const iowait = finiteNumber(value.iowait)
  const irq = finiteNumber(value.irq)
  const softirq = finiteNumber(value.softirq)
  const steal = finiteNumber(value.steal)
  const found: StatsBreakdown = {
    ...(user === undefined ? {} : { user }), ...(system === undefined ? {} : { system }), ...(nice === undefined ? {} : { nice }), ...(idle === undefined ? {} : { idle }),
    ...(iowait === undefined ? {} : { iowait }), ...(irq === undefined ? {} : { irq }), ...(softirq === undefined ? {} : { softirq }), ...(steal === undefined ? {} : { steal }),
  }
  return BREAKDOWN_KEYS.some((key) => found[key] !== undefined) ? found : undefined
}

function frequency(value: unknown): { average: number; max: number } | undefined {
  const average = isRec(value) ? finiteNumber(value.average) : undefined
  const max = isRec(value) ? finiteNumber(value.max) : undefined
  return average !== undefined && max !== undefined ? { average, max } : undefined
}

/** The optional parts of `cpu`. */
export function cpuExtras(source: Rec): Pick<StatsCpu, 'physical_cores' | 'core_of' | 'clusters' | 'breakdown' | 'frequency_mhz' | 'temperature_celsius'> {
  const physical = finiteNumber(source.physical_cores)
  const coreOf = numberList(source.core_of)
  const groups = clusters(source.clusters)
  const states = breakdown(source.breakdown)
  const speed = frequency(source.frequency_mhz)
  const temperature = finiteNumber(source.temperature_celsius)
  return {
    ...(physical === undefined ? {} : { physical_cores: physical }),
    ...(coreOf === undefined ? {} : { core_of: coreOf }),
    ...(groups === undefined ? {} : { clusters: groups }),
    ...(states === undefined ? {} : { breakdown: states }),
    ...(speed === undefined ? {} : { frequency_mhz: speed }),
    ...(temperature === undefined ? {} : { temperature_celsius: temperature }),
  }
}

/** The optional counters of `network`. */
export function networkExtras(source: Rec): Pick<StatsNetwork, 'errors_in_total' | 'errors_out_total' | 'drops_in_total' | 'drops_out_total'> {
  const errorsIn = finiteNumber(source.errors_in_total)
  const errorsOut = finiteNumber(source.errors_out_total)
  const dropsIn = finiteNumber(source.drops_in_total)
  const dropsOut = finiteNumber(source.drops_out_total)
  return {
    ...(errorsIn === undefined ? {} : { errors_in_total: errorsIn }), ...(errorsOut === undefined ? {} : { errors_out_total: errorsOut }),
    ...(dropsIn === undefined ? {} : { drops_in_total: dropsIn }), ...(dropsOut === undefined ? {} : { drops_out_total: dropsOut }),
  }
}

/** The optional top-level parts: disk speed and the number of running programs. */
export function topExtras(source: Rec): Pick<MachineStats, 'disk_io' | 'process_count'> {
  const speed = source.disk_io
  const read = isRec(speed) ? finiteNumber(speed.read_bytes_per_second) : undefined
  const write = isRec(speed) ? finiteNumber(speed.write_bytes_per_second) : undefined
  const count = finiteNumber(source.process_count)
  return {
    ...(read === undefined || write === undefined ? {} : { disk_io: { read_bytes_per_second: read, write_bytes_per_second: write } }),
    ...(count === undefined ? {} : { process_count: count }),
  }
}

export function processExtras(source: Rec): Pick<StatsProcess, 'threads'> {
  const threads = finiteNumber(source.threads)
  return threads === undefined ? {} : { threads }
}
