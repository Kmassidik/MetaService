// The rules of the Security page, in plain words: which check is fine and which needs a look, what each row says, what the card's badge says, and how
// counts and times are written. Pure functions; the page only draws what these return.
import type { MachineSecurity, SecurityBaseline } from './types.ts'

export type CheckState = 'ok' | 'warning' | 'unknown'
export type CheckId = 'password_login' | 'ban_tool' | 'firewall' | 'auto_updates' | 'starts_after_reboot' | 'pending_updates'

export interface BaselineRow {
  id: CheckId
  label: string
  /** One or two words for a chip in a table row. */
  short: string
  state: CheckState
  /** One plain line about what was found. */
  line: string
  /** What to do, in plain words; null when nothing needs doing. */
  todo: string | null
}

export const UNKNOWN_LINE = 'The helper did not say. It may be an old helper, or this check is not supported here.'
const DAYS_LABEL = '7 d'
const UNKNOWN_SHORT = 'unknown'

const ok = (id: CheckId, label: string, short: string, line: string): BaselineRow => ({ id, label, short, state: 'ok', line, todo: null })
const warn = (id: CheckId, label: string, short: string, line: string, todo: string): BaselineRow => ({ id, label, short, state: 'warning', line, todo })
const unknown = (id: CheckId, label: string, line = UNKNOWN_LINE): BaselineRow => ({ id, label, short: UNKNOWN_SHORT, state: 'unknown', line, todo: null })

function passwordRow({ password_login }: SecurityBaseline): BaselineRow {
  const label = 'Password login'
  if (password_login === null) return unknown('password_login', label)
  if (password_login) return warn('password_login', label, 'on', 'SSH accepts a password. Anyone on the internet can keep guessing it.', 'Turn off password login')
  return ok('password_login', label, 'off', 'Off. Only keys can log in.')
}

function banToolRow({ ban_tool }: SecurityBaseline): BaselineRow {
  const label = 'Ban tool'
  if (ban_tool === null) return unknown('ban_tool', label)
  if (ban_tool === 'not_available') return { ...unknown('ban_tool', label, 'A ban tool blocks an address that keeps failing to log in (Linux uses fail2ban). A Mac has no such tool, so MetaService only counts the failed logins and nobody is blocked. This is safe while password login is off: with only keys allowed, guessing cannot get in.'), short: 'n/a' }
  if (ban_tool === 'running') return ok('ban_tool', label, 'running', 'Running. Addresses that keep failing are blocked for a while.')
  return warn('ban_tool', label, 'stopped', 'No ban tool is running, so nobody is blocked automatically.', 'Install and start a ban tool (fail2ban)')
}

function onOffRow(id: CheckId, label: string, value: boolean | null, words: { yes: string; no: string }, good: string, bad: string, todo: string): BaselineRow {
  if (value === null) return unknown(id, label)
  return value ? ok(id, label, words.yes, good) : warn(id, label, words.no, bad, todo)
}

function pendingRow({ pending_updates }: SecurityBaseline): BaselineRow {
  const label = 'Pending updates'
  if (pending_updates === null) return unknown('pending_updates', label)
  if (pending_updates === 0) return ok('pending_updates', label, 'none', 'None. The machine is up to date.')
  const noun = pending_updates === 1 ? 'update is' : 'updates are'
  return warn('pending_updates', label, String(pending_updates), `${pending_updates} security ${noun} waiting.`, pending_updates === 1 ? 'Install the security update' : 'Install the security updates')
}

/** One row per check, always in the same order, whatever the machine reports. */
export function baselineRows(base: SecurityBaseline): BaselineRow[] {
  return [
    passwordRow(base),
    banToolRow(base),
    onOffRow('firewall', 'Firewall', base.firewall, { yes: 'on', no: 'off' }, 'On.', 'The firewall is off, so every open port is reachable.', 'Turn on the firewall'),
    onOffRow('auto_updates', 'Auto updates', base.auto_updates, { yes: 'on', no: 'off' }, 'On. Fixes install by themselves.', 'Security fixes wait for someone to install them.', 'Turn on automatic security updates'),
    onOffRow('starts_after_reboot', 'Starts after reboot', base.starts_after_reboot, { yes: 'yes', no: 'no' }, 'Yes. The machine comes back by itself.', 'After a reboot the helper stays off until someone starts it.', 'Make the helper start after a reboot'),
    pendingRow(base),
  ]
}

export const warningCount = (report: MachineSecurity): number => baselineRows(report.baseline).filter((row) => row.state === 'warning').length

/** A count with thousands separators, or a dash when the helper did not count. */
export const numberText = (value: number | null): string => (value === null ? '–' : value.toLocaleString('en-US'))

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
