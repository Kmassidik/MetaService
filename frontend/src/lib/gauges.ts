// The gauge row at the top of the Live tab: five arcs (CPU, memory, 5 minute load, swap, disk) with their numbers, and a sixth for the GPU on a machine that reports its use. Pure functions, no DOM.
import { gaugeLevel, type GaugeLevel } from './charts.ts'
import { formatBytes, formatLoad, formatPercent, MEASURING_TEXT, percentOf } from './stats.ts'
import type { MachineStats, StatsDisk } from './types.ts'

const FULL = 100

export interface GaugeSpec {
  key: 'cpu' | 'memory' | 'load' | 'swap' | 'disk' | 'gpu'
  label: string
  /** The arc fill, 0 to 100; null draws an empty arc. */
  percent: number | null
  /** The number in the middle. */
  value: string
  /** A small line under it. */
  caption: string
  level: GaugeLevel
  /** What a screen reader hears: "CPU 12 percent". */
  describe: string
}

/** The root volume when there is one, otherwise the first. */
export const rootDisk = (disks: readonly StatsDisk[]): StatsDisk | null => disks.find((disk) => disk.mount === '/') ?? disks[0] ?? null

const percentWord = (percent: number): string => `${Math.round(percent)} percent`

function percentGauge(key: GaugeSpec['key'], label: string, percent: number | null, caption: string): GaugeSpec {
  const value = percent === null ? MEASURING_TEXT : formatPercent(percent)
  return { key, label, percent, value, caption, level: gaugeLevel(percent), describe: percent === null ? `${label} still being measured` : `${label} ${percentWord(percent)}` }
}

/** The 5 minute load against the number of CPUs: a load equal to the CPU count is a full arc. */
export function loadGauge(stats: MachineStats): GaugeSpec {
  const five = stats.cpu.load.five
  const percent = five === null ? null : Math.min(FULL, percentOf(five, stats.cpu.core_count))
  return {
    key: 'load', label: 'Load (5 min)', percent, value: five === null ? '–' : formatLoad(five), caption: `of ${stats.cpu.core_count} CPUs`, level: gaugeLevel(percent),
    describe: five === null ? 'Load not known' : `Load over 5 minutes ${formatLoad(five)} on ${stats.cpu.core_count} CPUs`,
  }
}

function swapGauge(stats: MachineStats): GaugeSpec {
  const { swap_total_bytes: total, swap_used_bytes: used } = stats.memory
  if (total <= 0) return { key: 'swap', label: 'Swap', percent: null, value: 'none', caption: 'no swap on this computer', level: 'normal', describe: 'Swap: this computer has none' }
  return percentGauge('swap', 'Swap', percentOf(used, total), `${formatBytes(used)} of ${formatBytes(total)}`)
}

function diskGauge(stats: MachineStats): GaugeSpec {
  const disk = rootDisk(stats.disks)
  if (disk === null) return { key: 'disk', label: 'Disk', percent: null, value: '–', caption: 'no disk reported', level: 'normal', describe: 'Disk: none reported' }
  return percentGauge('disk', 'Disk', percentOf(disk.used_bytes, disk.total_bytes), `${disk.mount} · ${formatBytes(disk.used_bytes)} of ${formatBytes(disk.total_bytes)}`)
}

/** The busiest GPU's use. None when no GPU says how busy it is (an Intel GPU does not without root): an empty arc would read as idle. */
export function gpuGauge(stats: MachineStats): GaugeSpec | null {
  const busy = stats.gpus.flatMap((gpu, index) => (gpu.utilization_percent === null ? [] : [{ index, use: gpu.utilization_percent }]))
  const busiest = busy.reduce<{ index: number; use: number } | null>((best, one) => (best === null || one.use > best.use ? one : best), null)
  if (busiest === null) return null
  const many = stats.gpus.length > 1
  return percentGauge('gpu', 'GPU', busiest.use, many ? `busiest of ${stats.gpus.length} GPUs` : (stats.gpus[busiest.index]?.name ?? 'GPU'))
}

export function gaugeSpecs(stats: MachineStats): GaugeSpec[] {
  const { memory } = stats
  const gpu = gpuGauge(stats)
  return [
    percentGauge('cpu', 'CPU', stats.cpu.total_percent, `${stats.cpu.core_count} CPUs`),
    percentGauge('memory', 'Memory', percentOf(memory.used_bytes, memory.total_bytes), `${formatBytes(memory.used_bytes)} of ${formatBytes(memory.total_bytes)}`),
    loadGauge(stats),
    swapGauge(stats),
    diskGauge(stats),
    ...(gpu === null ? [] : [gpu]),
  ]
}
