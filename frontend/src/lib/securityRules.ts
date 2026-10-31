// The rules of the Security tab, in plain words: which check is fine and which needs a look, what each row says, how lists are ordered, what the card's badge
// says, and how tall each bar of the chart is. Pure functions over a MachineSecurity; the page only draws what these return.
import type { AcceptedLogin, BlockedAddress, BotName, MachineSecurity, SecurityBaseline, SecurityWindows } from './types.ts'

export type CheckState = 'ok' | 'warning' | 'unknown'
export type CheckId = 'password_login' | 'ban_tool' | 'firewall' | 'auto_updates' | 'starts_after_reboot' | 'pending_updates'

export interface BaselineRow {
  id: CheckId
  label: string
  state: CheckState
  /** One plain line about what was found. */
  line: string
  /** What to do, in plain words; null when nothing needs doing. */
  todo: string | null
}

/** How many user names the "Names the bots try" block shows. */
export const TOP_NAMES = 8
export const UNKNOWN_LINE = 'The helper did not say. It may be an old helper, or this check is not supported here.'
const DAYS_LABEL = '7 d'

const ok = (id: CheckId, label: string, line: string): BaselineRow => ({ id, label, state: 'ok', line, todo: null })
const warn = (id: CheckId, label: string, line: string, todo: string): BaselineRow => ({ id, label, state: 'warning', line, todo })
const unknown = (id: CheckId, label: string, line = UNKNOWN_LINE): BaselineRow => ({ id, label, state: 'unknown', line, todo: null })

function passwordRow({ password_login }: SecurityBaseline): BaselineRow {
  const label = 'Password login for SSH'
  if (password_login === null) return unknown('password_login', label)
  if (password_login) return warn('password_login', label, 'SSH accepts a password. Anyone on the internet can keep guessing it.', 'Turn off password login')
  return ok('password_login', label, 'Off. Only keys can log in.')
}

function banToolRow({ ban_tool }: SecurityBaseline): BaselineRow {
  const label = 'Ban tool'
  if (ban_tool === null) return unknown('ban_tool', label)
  if (ban_tool === 'not_available') return unknown('ban_tool', label, 'Not available on this kind of computer. Failed logins are counted, but nobody is blocked.')
  if (ban_tool === 'running') return ok('ban_tool', label, 'Running. Addresses that keep failing are blocked for a while.')
  return warn('ban_tool', label, 'No ban tool is running, so nobody is blocked automatically.', 'Install and start a ban tool (fail2ban)')
}

function onOffRow(id: CheckId, label: string, value: boolean | null, good: string, bad: string, todo: string): BaselineRow {
  if (value === null) return unknown(id, label)
  return value ? ok(id, label, good) : warn(id, label, bad, todo)
}

function pendingRow({ pending_updates }: SecurityBaseline): BaselineRow {
  const label = 'Pending security updates'
  if (pending_updates === null) return unknown('pending_updates', label)
  if (pending_updates === 0) return ok('pending_updates', label, 'None. The machine is up to date.')
  const noun = pending_updates === 1 ? 'update is' : 'updates are'
  return warn('pending_updates', label, `${pending_updates} security ${noun} waiting.`, pending_updates === 1 ? 'Install the security update' : 'Install the security updates')
}

/** One row per check, always in the same order, whatever the machine reports. */
export function baselineRows(report: MachineSecurity): BaselineRow[] {
  const base = report.baseline
  return [
    passwordRow(base),
    banToolRow(base),
    onOffRow('firewall', 'Firewall', base.firewall, 'On.', 'The firewall is off, so every open port is reachable.', 'Turn on the firewall'),
    onOffRow('auto_updates', 'Automatic security updates', base.auto_updates, 'On. Fixes install by themselves.', 'Security fixes wait for someone to install them.', 'Turn on automatic security updates'),
    onOffRow('starts_after_reboot', 'Helper starts after a reboot', base.starts_after_reboot, 'Yes. The machine comes back by itself.', 'After a reboot the helper stays off until someone starts it.', 'Make the helper start after a reboot'),
    pendingRow(base),
  ]
}

export const warningCount = (report: MachineSecurity): number => baselineRows(report).filter((row) => row.state === 'warning').length

/** A count with thousands separators, or a dash when the helper did not count. */
export const numberText = (value: number | null): string => (value === null ? '–' : value.toLocaleString('en-US'))

const counted = (count: number, one: string, many: string) => `${numberText(count)} ${count === 1 ? one : many}`

/** The line at the top of the summary, e.g. "96,214 failed logins and 24 blocked addresses in the last 30 days". */
export function summaryHeadline(windows: SecurityWindows): string {
  const { failed, blocked } = windows.d30
  if (failed === null || blocked === null) return 'The helper has not counted the last 30 days yet.'
  return `${counted(failed, 'failed login', 'failed logins')} and ${counted(blocked, 'blocked address', 'blocked addresses')} in the last 30 days.`
}

export interface Badge {
  text: string
  /** A baseline check needs a look. */
  warning: boolean
}

const WARNING_DOT = '●'

/** The small badge on a machine card; null when the machine does not report. */
export function securityBadge(report: MachineSecurity | null): Badge | null {
  if (report === null) return null
  const warning = warningCount(report) > 0
  const blocked = report.windows.d7.blocked
  const blockedText = blocked === null ? '' : `${numberText(blocked)} blocked · ${DAYS_LABEL}`
  if (!warning) return blockedText === '' ? null : { text: blockedText, warning }
  return { text: blockedText === '' ? `${WARNING_DOT} Security` : `${WARNING_DOT} ${blockedText}`, warning }
}

/** Why the table of blocked addresses is empty, said honestly: no one is blocked, or no tool is blocking. */
export function blockedEmptyText(report: MachineSecurity): string {
  const tool = report.baseline.ban_tool
  if (tool === 'running') return 'No address is blocked right now.'
  if (tool === 'not_available') return 'This kind of computer has no ban tool, so nothing is blocked. Failed logins are only counted.'
  if (tool === 'not_running') return 'No ban tool is running, so nothing is blocked. An empty list here does not mean nobody is knocking.'
  return 'The helper has not said whether a ban tool is running, so there is nothing to show.'
}

const time = (iso: string | null): number => (iso === null ? Number.NEGATIVE_INFINITY : Date.parse(iso))

/** Newest block first; a block with no date goes last. */
export const orderBlocked = (rows: BlockedAddress[]): BlockedAddress[] => [...rows].sort((a, b) => time(b.since) - time(a.since))

/** The names the bots try most, biggest first, at most TOP_NAMES. Equal counts keep the helper's order. */
export const topNames = (rows: BotName[]): BotName[] => [...rows].sort((a, b) => b.count - a.count).slice(0, TOP_NAMES)

/** Password logins first (they should not exist), then the most recent. */
export function orderLogins(rows: AcceptedLogin[]): AcceptedLogin[] {
  const rank = (login: AcceptedLogin) => (login.method === 'password' ? 0 : 1)
  return [...rows].sort((a, b) => rank(a) - rank(b) || time(b.last_seen) - time(a.last_seen))
}

/** Each bar's height as a share of the tallest bar, 0 to 1, drawn to scale from zero; a day with no count is null (no bar). */
export function barShares(days: (number | null)[]): (number | null)[] {
  const tallest = Math.max(0, ...days.map((day) => day ?? 0))
  return days.map((day) => (day === null ? null : day / Math.max(1, tallest)))
}

/** How long ago a bar is: the last one is today. */
export function dayLabel(index: number, total: number): string {
  const ago = total - 1 - index
  if (ago === 0) return 'today'
  return ago === 1 ? 'yesterday' : `${ago} days ago`
}

const MINUTE_MS = 60_000
const HOUR_MS = 60 * MINUTE_MS
const DAY_MS = 24 * HOUR_MS

function span(ms: number): string {
  if (ms < HOUR_MS) return `${Math.max(1, Math.round(ms / MINUTE_MS))}m`
  return ms < DAY_MS ? `${Math.floor(ms / HOUR_MS)}h` : `${Math.floor(ms / DAY_MS)}d`
}

/** When a block ends: "in 3h" while it lasts, "ended 2h ago" after, a dash when the date is missing. */
export function blockEndText(iso: string | null, now: number): string {
  const end = iso === null ? Number.NaN : Date.parse(iso)
  if (Number.isNaN(end)) return '–'
  return end > now ? `in ${span(end - now)}` : `ended ${span(now - end)} ago`
}

/** Share of the biggest count, for the small bars of the user names. */
export function nameShares(rows: BotName[]): number[] {
  const biggest = Math.max(1, ...rows.map((row) => row.count))
  return rows.map((row) => row.count / biggest)
}
