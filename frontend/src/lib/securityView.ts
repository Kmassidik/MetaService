// What the Security page shows, worked out from the machines the panel knows and the overview the parent gave: one table line for EVERY machine (a machine that
// has not reported is "Not watched", never a row of zeros), the top lists, and the plain words around them. Pure functions; the components only draw what these return.
import { baselineRows, type BaselineRow } from './securityRules.ts'
import type { SecurityOverview, TopRow } from './securityTypes.ts'
import type { Machine, MachineState } from './types.ts'

/** The plain line a machine without security data gets. */
export const NOT_WATCHED_LINE = 'no security data yet'
export const NOT_WATCHED_LABEL = 'Not watched'
/** The banner when the parent has no security API at all. */
export const NOT_COLLECTED_BANNER = 'Security data is not collected yet. Nothing here is being watched.'
/** How many user names and addresses each top list shows. */
export const TOP_SHOWN = 8

/** A machine as the Security page needs it: the panel's own list, or the sample's. */
export interface MachineInfo {
  id: string
  name: string
  state: MachineState
}

export interface MachineSecurityRow extends MachineInfo {
  watched: boolean
  lastReported: string | null
  /** The six baseline checks; empty for a machine that is not watched. */
  checks: BaselineRow[]
  failed: number | null
  blocked: number | null
}

export const infoOf = (machines: Machine[]): MachineInfo[] => machines.map(({ id, name, state }) => ({ id, name, state }))

/** One row per machine, in the order the machines came, whether or not the overview mentions them. */
export function machineRows(infos: MachineInfo[], overview: SecurityOverview | null): MachineSecurityRow[] {
  return infos.map((info) => {
    const line = overview?.machines.find((one) => one.machine === info.id)
    if (line === undefined || !line.reported) return { ...info, watched: false, lastReported: null, checks: [], failed: null, blocked: null }
    return { ...info, watched: true, lastReported: line.last_reported, checks: baselineRows(line.baseline), failed: line.failed, blocked: line.blocked }
  })
}

/** The name to show for a machine id; the id itself when the machine is not in the list. */
export const nameOf = (infos: MachineInfo[], id: string): string => infos.find((info) => info.id === id)?.name ?? id

/** The biggest rows first, at most TOP_SHOWN; equal counts keep the parent's order. */
export const topShown = (rows: TopRow[]): TopRow[] => [...rows].sort((a, b) => b.count - a.count).slice(0, TOP_SHOWN)

/** Each row's share of the biggest row, 0 to 1, for the small bars. */
export function topShares(rows: TopRow[]): number[] {
  const biggest = Math.max(1, ...rows.map((row) => row.count))
  return rows.map((row) => row.count / biggest)
}

/** True when at least one machine is watched, so the page has something to say about the range. */
export const anyWatched = (rows: MachineSecurityRow[]): boolean => rows.some((row) => row.watched)
