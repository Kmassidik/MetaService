// What the CPU card says about the processor: cores against threads, the per-thread bars grouped by core, frequency and temperature. Pure functions, no DOM.
import type { StatsCpu } from './types.ts'

const MHZ_PER_GHZ = 1000

export interface ThreadBar {
  /** Position in the machine's own list of CPUs, from 0. */
  cpu: number
  percent: number
  /** What a pointer or a keyboard focus says: "core 3 thread 2 · 42%". */
  label: string
}

export interface CoreGroup {
  /** The physical core as people count it, from 1. */
  core: number
  threads: ThreadBar[]
}

const plural = (count: number, one: string, many: string): string => `${count} ${count === 1 ? one : many}`

/** "4 performance + 6 efficiency" when the system names groups, "16 cores · 32 threads" with hyper-threading, "10 cores" without, "8 CPUs" when only the count is known. */
export function topologyLine(cpu: StatsCpu): string {
  if (cpu.clusters !== undefined && cpu.clusters.length > 0) return cpu.clusters.map((cluster) => `${cluster.logical} ${cluster.name.toLowerCase()}`).join(' + ')
  const physical = cpu.physical_cores
  if (physical === undefined) return plural(cpu.core_count, 'CPU', 'CPUs')
  if (physical === cpu.core_count) return plural(physical, 'core', 'cores')
  return `${plural(physical, 'core', 'cores')} · ${plural(cpu.core_count, 'thread', 'threads')}`
}

/** "core 3 thread 2" for a core with siblings, "core 3" for a core of one thread, "CPU 3" when the machine does not say which are cores. */
function barName(core: number, thread: number, siblings: number, coresKnown: boolean): string {
  if (siblings > 1) return `core ${core} thread ${thread}`
  return coresKnown ? `core ${core}` : `CPU ${core}`
}

const percentText = (percent: number): string => `${Math.round(percent)}%`

/** The per-CPU bars, siblings of one physical core next to each other, cores in order. Without a grouping every CPU is its own group. */
export function threadGroups(cpu: StatsCpu): CoreGroup[] {
  const percents = cpu.cores_percent ?? []
  const coreOf = cpu.core_of !== undefined && cpu.core_of.length === percents.length ? cpu.core_of : null
  const known = cpu.physical_cores !== undefined
  const byCore = new Map<number, number[]>()
  percents.forEach((_, index) => {
    const core = coreOf?.[index] ?? index
    byCore.set(core, [...(byCore.get(core) ?? []), index])
  })
  return [...byCore.entries()].sort(([a], [b]) => a - b).map(([, cpus], position): CoreGroup => ({
    core: position + 1,
    threads: cpus.map((index, thread): ThreadBar => {
      const percent = percents[index] ?? 0
      return { cpu: index, percent, label: `${barName(position + 1, thread + 1, cpus.length, known)} · ${percentText(percent)}` }
    }),
  }))
}

/** "4.2 GHz (up to 4.9 GHz)"; a speed that is not there says nothing. */
export function frequencyText(frequency: StatsCpu['frequency_mhz']): string | null {
  if (frequency === undefined) return null
  const ghz = (mhz: number): string => `${(mhz / MHZ_PER_GHZ).toFixed(1)} GHz`
  return `${ghz(frequency.average)} (up to ${ghz(frequency.max)})`
}

export function temperatureText(celsius: number | undefined): string | null {
  return celsius === undefined ? null : `${Math.round(celsius)} °C`
}
