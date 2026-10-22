// What the Top processes window lists: every program the machine reported (at most 15), or the ones that match what was typed. Pure functions, no DOM.
import type { MachineStatsReply, StatsProcess } from './types.ts'

const matches = (process: StatsProcess, needle: string): boolean => process.name.toLowerCase().includes(needle) || process.user.toLowerCase().includes(needle)

/** The programs whose name or account holds what was typed (letter case and spaces around it do not matter); with nothing typed, all of them. */
export function filterProcesses(processes: readonly StatsProcess[], filter: string): StatsProcess[] {
  const needle = filter.trim().toLowerCase()
  return needle === '' ? [...processes] : processes.filter((process) => matches(process, needle))
}

/** The list a reply carries, or null when it was asked without the list or has no numbers. An empty list from a reply that asked for it stays empty. */
export function processesFromReply(reply: MachineStatsReply, askedForList: boolean): StatsProcess[] | null {
  if (!askedForList || !reply.stats) return null
  return reply.stats.processes
}

export type ProcessSort = 'cpu' | 'memory'

/** The programs busiest first by the chosen number; a program with no CPU yet comes last, and ties keep the order of the list. */
export function sortProcesses(processes: readonly StatsProcess[], by: ProcessSort): StatsProcess[] {
  const value = (process: StatsProcess): number => (by === 'cpu' ? (process.cpu_percent ?? Number.NEGATIVE_INFINITY) : process.memory_bytes)
  return processes.map((process, index) => ({ process, index })).sort((a, b) => value(b.process) - value(a.process) || a.index - b.index).map(({ process }) => process)
}

/** The value of `aria-sort` for a column header: the sorted column says descending, the others say nothing. */
export const ariaSortOf = (column: ProcessSort, sorted: ProcessSort): 'descending' | 'none' => (column === sorted ? 'descending' : 'none')
