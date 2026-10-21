// Pure helpers for the live monitor: units, percentages, bar widths, the short history, "measuring" and "offline". No DOM, no network.
import { formatGb, formatMb, relativeTime } from './format.ts'
import type { MachineStats, MachineStatsReply, Workload } from './types.ts'

/** How often a machine's own page asks for a reading, and how often the Machines list does. */
export const MACHINE_PAGE_POLL_MS = 5000
export const LIST_POLL_MS = 15000
/** The history kept in the browser: 60 readings, 5 minutes at 5 seconds. */
export const HISTORY_LIMIT = 60
const KIB = 1024
const UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
const SECONDS_PER_MINUTE = 60
const SECONDS_PER_HOUR = 3600
const SECONDS_PER_DAY = 86400
const FULL = 100
const SMALL_CORE_GRID = 8
const WIDE_CORE_GRID = 16
export const MEASURING_TEXT = 'measuring…'

function trimmed(value: number): string {
  return value >= 100 ? String(Math.round(value)) : value.toFixed(1).replace(/\.0$/, '')
}

/** 1536 -> "1.5 KB". Units of 1024, named like the rest of the panel. */
export function formatBytes(bytes: number): string {
  let value = Math.max(0, bytes)
  let unit = 0
  while (value >= KIB && unit < UNITS.length - 1) {
    value /= KIB
    unit += 1
  }
  return `${unit === 0 ? Math.round(value) : trimmed(value)} ${UNITS[unit]}`
}

/** Bytes per second, or "measuring…" while the machine has no earlier reading to compare with. */
export function formatRate(bytesPerSecond: number | null): string {
  return bytesPerSecond === null ? MEASURING_TEXT : `${formatBytes(bytesPerSecond)}/s`
}

export function formatPercent(percent: number | null): string {
  return percent === null ? '–' : `${Math.round(percent)}%`
}

/** A process uses percent of ONE core, so it can pass 100. */
export function formatProcessCpu(percent: number | null): string {
  return percent === null ? '–' : `${percent.toFixed(1)}%`
}

export function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / SECONDS_PER_DAY)
  const hours = Math.floor((seconds % SECONDS_PER_DAY) / SECONDS_PER_HOUR)
  const minutes = Math.floor((seconds % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

export function formatLoad(load: number | null): string {
  return load === null ? '–' : load.toFixed(2)
}

/** part of total as a percent from 0 to 100; 0 when the total is empty. */
export function percentOf(part: number, total: number): number {
  if (total <= 0) return 0
  return Math.min(FULL, Math.max(0, (part / total) * FULL))
}

/** The width of a bar for a percent, as CSS. A reading that is not there yet is an empty bar. */
export function barWidth(percent: number | null): string {
  if (percent === null || Number.isNaN(percent)) return '0%'
  return `${Math.min(FULL, Math.max(0, percent)).toFixed(1).replace(/\.0$/, '')}%`
}

/** Used, cached and free as widths that never pass 100 together. */
export function memorySegments(memory: MachineStats['memory']): { used: number; cached: number; free: number } {
  const used = percentOf(memory.used_bytes, memory.total_bytes)
  const cached = Math.min(FULL - used, percentOf(memory.cached_bytes, memory.total_bytes))
  const free = Math.min(FULL - used - cached, percentOf(memory.free_bytes, memory.total_bytes))
  return { used, cached, free }
}

/** How many columns the per-core grid has: one row for a few cores, 8 or 16 across for many, so 32 cores stay small. */
export function coreColumns(count: number): number {
  if (count <= SMALL_CORE_GRID) return Math.max(1, count)
  return count <= WIDE_CORE_GRID ? SMALL_CORE_GRID : WIDE_CORE_GRID
}

/** The first answer after a start has no earlier reading to compare with. */
export const isMeasuring = (stats: MachineStats): boolean => stats.measuring

/** The helper on the machine is too old to answer: say so, show no numbers. */
export const needsHelperUpdate = (reply: MachineStatsReply): boolean => reply.state === 'old_helper'

/** Offline, or a reading that came with no helper behind it: show it greyed, never as live. */
export const isStale = (reply: MachineStatsReply): boolean => reply.state === 'offline'

export function offlineText(reply: MachineStatsReply, now: number): string {
  return `offline, last seen ${relativeTime(reply.last_seen, now)}`
}

/** One point of the short graphs. */
export interface HistoryPoint {
  cpu: number | null
  memory: number
  down: number | null
  up: number | null
}

export function historyPoint(stats: MachineStats): HistoryPoint {
  return {
    cpu: stats.cpu.total_percent,
    memory: percentOf(stats.memory.used_bytes, stats.memory.total_bytes),
    down: stats.network.received_bytes_per_second,
    up: stats.network.sent_bytes_per_second,
  }
}

/** The history with one more point, the oldest dropped past the limit. Returns a new list. */
export function pushHistory<T>(history: readonly T[], point: T, limit: number = HISTORY_LIMIT): T[] {
  return [...history, point].slice(-limit)
}

/** The drawing of a graph: line segments in a box, broken where a value is missing. */
export function sparkPath(values: readonly (number | null)[], width: number, height: number, ceiling: number): string {
  if (values.length < 2 || ceiling <= 0) return ''
  const step = width / (values.length - 1)
  let path = ''
  let pen = false
  values.forEach((value, index) => {
    if (value === null) {
      pen = false
      return
    }
    const y = height - Math.min(1, Math.max(0, value / ceiling)) * height
    path += `${pen ? 'L' : 'M'}${(index * step).toFixed(1)} ${y.toFixed(1)}`
    pen = true
  })
  return path
}

/** The biggest value in a series, at least `floor`, so a quiet network does not draw as a full-height line. */
export function ceilingOf(values: readonly (number | null)[], floor: number): number {
  return values.reduce<number>((top, value) => (value !== null && value > top ? value : top), floor)
}

/** The one small line about what VMs have reserved: running VMs hold cores and memory, every VM keeps its disk. */
export function reservedText(workloads: readonly Workload[]): string {
  if (workloads.length === 0) return 'No VMs have reserved anything yet.'
  const running = workloads.filter((workload) => workload.state === 'running')
  const cores = running.reduce((sum, workload) => sum + workload.cpu, 0)
  const memoryMb = running.reduce((sum, workload) => sum + workload.ram_mb, 0)
  const diskGb = workloads.reduce((sum, workload) => sum + workload.disk_gb, 0)
  return `VMs have reserved ${cores} ${cores === 1 ? 'core' : 'cores'}, ${formatMb(memoryMb)} memory, ${formatGb(diskGb)} disk`
}
