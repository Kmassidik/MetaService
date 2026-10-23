// Pure helpers for the live monitor: units, percentages, bar widths, the short history, "measuring" and "offline". No DOM, no network.
import { formatGb, formatMb, relativeTime } from './format.ts'
import type { MachineStatsReply, Workload } from './types.ts'

/** How often the Machines list asks for a reading. */
export const LIST_POLL_MS = 15000
/** How often a machine's page asks while a person watches its Live tab: the parent shares one helper reading per 1.5 s, so each ask gets a new one. */
export const LIVE_FAST_POLL_MS = 2000
/** The wait after a failed ask, so a parent that cannot answer is not asked every 2 seconds. */
export const FAILED_POLL_MS = 5000

export interface PollState {
  /** The Live tab of the machine's page is the tab shown. */
  liveTabVisible: boolean
  /** The browser tab is shown (`document.visibilityState === 'visible'`). */
  pageVisible: boolean
  /** The last ask failed. */
  failed: boolean
}

/** The wait before the next ask for the machine's page, or null when nobody is watching and nothing should be asked. */
export function pollIntervalMs({ liveTabVisible, pageVisible, failed }: PollState): number | null {
  if (!liveTabVisible || !pageVisible) return null
  return failed ? FAILED_POLL_MS : LIVE_FAST_POLL_MS
}
/** The address of a machine's reading. `withProcesses` false asks the parent to leave the list of programs out, which spares the machine the scan. */
export const statsPath = (id: string, withProcesses: boolean): string => `/api/machines/${encodeURIComponent(id)}/stats?processes=${withProcesses ? 1 : 0}`

const KIB = 1024
const UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
const SECONDS_PER_MINUTE = 60
const SECONDS_PER_HOUR = 3600
const SECONDS_PER_DAY = 86400
const FULL = 100
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

/** The helper on the machine is too old to answer: say so, show no numbers. */
export const needsHelperUpdate = (reply: MachineStatsReply): boolean => reply.state === 'old_helper'

/** Offline, or a reading that came with no helper behind it: show it greyed, never as live. */
export const isStale = (reply: MachineStatsReply): boolean => reply.state === 'offline'

export function offlineText(reply: MachineStatsReply, now: number): string {
  return `offline, last seen ${relativeTime(reply.last_seen, now)}`
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
