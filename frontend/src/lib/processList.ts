// Which programs the Live tab lists: the top few, all of them on request, or the ones that match what was typed. Pure functions, no DOM.
import type { StatsProcess } from './types.ts'

export const TOP_PROCESSES = 5

export interface ProcessView {
  rows: StatsProcess[]
  /** How many programs the machine reported. */
  total: number
  /** There are more rows than the short list shows, so "Show all" means something. */
  canExpand: boolean
}

const matches = (process: StatsProcess, needle: string): boolean => process.name.toLowerCase().includes(needle) || process.user.toLowerCase().includes(needle)

/** A filter searches every program and shows every match; without one, the short list is the first rows unless `showAll`. */
export function visibleProcesses(processes: readonly StatsProcess[], filter: string, showAll: boolean): ProcessView {
  const needle = filter.trim().toLowerCase()
  const total = processes.length
  if (needle !== '') return { rows: processes.filter((process) => matches(process, needle)), total, canExpand: false }
  return { rows: showAll ? [...processes] : processes.slice(0, TOP_PROCESSES), total, canExpand: total > TOP_PROCESSES }
}
