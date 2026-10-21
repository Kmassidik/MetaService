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
