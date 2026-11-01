// What the Security page shows, worked out from the machines the panel knows and the overview the parent gave: one table line for EVERY machine (a machine that
// has not reported is "Not watched", never a row of zeros), the top lists, and the plain words around them. Pure functions; the components only draw what these return.
import { baselineRows, type BaselineRow } from './securityRules.ts'
import { EVENT_TYPE_LABELS, type SecurityEvent, type SecurityOverview, type TopRow } from './securityTypes.ts'
import { RANGE_PHRASE } from './securityRanges.ts'
import type { SecurityRange } from './securityTypes.ts'
import type { HelperUpdateInfo, Machine, MachineState } from './types.ts'

/** The plain line a machine that is online but sends no security data gets. */
export const NOT_WATCHED_LINE = 'No security data yet: its helper may be old'
/** The line of a machine that is switched off or cannot be reached: nothing can be asked of it now, and no button is offered. */
export const OFFLINE_LINE = 'The machine is offline.'
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
  /** The operating system the machine reported ("macos", "linux"). */
  os: string
  /** The helper program's build and whether a newer one is on offer (the Update helper button of a machine that is not watched). */
  agent_build?: string | null
  update?: HelperUpdateInfo
}

export interface MachineSecurityRow extends MachineInfo {
  watched: boolean
  lastReported: string | null
  /** The six baseline checks; empty for a machine that is not watched. */
  checks: BaselineRow[]
  failed: number | null
  blocked: number | null
}

export const infoOf = (machines: Machine[]): MachineInfo[] =>
  machines.map(({ id, name, state, os, agent_build, update }) => ({ id, name, state, os, ...(agent_build === undefined ? {} : { agent_build }), ...(update === undefined ? {} : { update }) }))

/** What a machine that does not report says in its Baseline cell, besides the Not watched tag. Never a number. */
export const notWatchedLine = (row: Pick<MachineSecurityRow, 'state'>): string => (row.state === 'offline' ? OFFLINE_LINE : NOT_WATCHED_LINE)

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

/** The words the parent stores for a Mac's daily count of SSH connections (macOS does not log who connected, so it is saved as a failed login without user or address). */
export const CONNECTION_DETAIL_PREFIX = 'SSH connections'
export const CONNECTION_TYPE_LABEL = 'SSH connections'
export const CONNECTION_TOOLTIP = "macOS does not record who connected. This counts every SSH connection that day, including MetaService's own tunnels and your own logins."
export const MAC_NOTE = 'Mac numbers count connections, not failed logins: macOS does not log who connected.'
const MAC_OS_NAMES: readonly string[] = ['macos', 'darwin']

/** True for a machine that runs macOS. */
export const isMacOs = (os: string): boolean => MAC_OS_NAMES.includes(os.trim().toLowerCase())

/** True for a Mac's daily count of SSH connections: a failed login with no user, no address and the detail the parent gives it. */
export const isConnectionCount = (event: SecurityEvent): boolean =>
  event.type === 'failed_login' && event.user === null && event.address === null && (event.detail ?? '').startsWith(CONNECTION_DETAIL_PREFIX)

/** The type column: the name of the event type, or "SSH connections" for a Mac's connection count. */
export const eventTypeLabel = (event: SecurityEvent): string => (isConnectionCount(event) ? CONNECTION_TYPE_LABEL : EVENT_TYPE_LABELS[event.type])

/** The tooltip of the type tag; only a connection count has one. */
export const eventTypeTitle = (event: SecurityEvent): string | undefined => (isConnectionCount(event) ? CONNECTION_TOOLTIP : undefined)

const countText = (count: number, one: string, many: string): string => `${count.toLocaleString('en-US')} ${count === 1 ? one : many}`

/** The detail column: for a failed login how many tries the row stands for, then what the helper said. A connection count says connections and leaves out the helper's wording. */
export function eventDetailText(event: SecurityEvent): string {
  if (isConnectionCount(event)) return event.count === null ? '' : countText(event.count, 'connection', 'connections')
  const tries = event.count === null ? null : countText(event.count, 'try', 'tries')
  return [tries, event.detail].filter((part) => part !== null).join(' · ')
}

/** True for a login that got in with a password: these should not exist, so the row is highlighted. */
export const isPasswordLogin = (event: SecurityEvent): boolean => event.type === 'login' && event.method === 'password'

/** The colour of the type tag: a password login and a block are marked, a key login is fine, the rest are plain. */
export function eventTone(event: SecurityEvent): 'run' | 'warn' | '' {
  if (isConnectionCount(event)) return ''
  if (isPasswordLogin(event) || event.type === 'blocked') return 'warn'
  return event.type === 'login' ? 'run' : ''
}

/** One plain sentence on the range: failed logins on the watched Linux machines and SSH connections on the Macs, in the range's own words ("in the last 6 hours"). Null when nothing is watched. */
export function rangeSummary(rows: MachineSecurityRow[], range: SecurityRange): string | null {
  const watched = rows.filter((row) => row.watched)
  if (watched.length === 0) return null
  const sum = (part: MachineSecurityRow[]): number => part.reduce((total, row) => total + (row.failed ?? 0), 0)
  const macs = watched.filter((row) => isMacOs(row.os))
  const others = watched.filter((row) => !isMacOs(row.os))
  const parts = [others.length > 0 ? countText(sum(others), 'failed login', 'failed logins') : null, macs.length > 0 ? countText(sum(macs), 'SSH connection', 'SSH connections') : null]
  return `${parts.filter((part) => part !== null).join(' and ')} ${RANGE_PHRASE[range]}.`
}
