// Reads a machine's `security` report the way the helper sent it, defensively: a value of the wrong type is dropped (a count becomes "unknown", a row
// is left out), text is cleaned and cut short, and every list is capped. Nothing here is trusted: a user name or an address comes from an attacker, so
// it is only ever a string to show as plain text. Pure functions, no DOM, no network. A machine that sent nothing readable gives null: "not reporting".
import { MAX_TEXT, clean, flag, isRec, rows, when, whole } from './securityPrims.ts'
import type {
  AcceptedLogin, BanToolState, BlockedAddress, BotName, LoginMethod, Machine, MachineSecurity, SecurityBaseline, SecurityCount, SecurityWindows,
} from './types.ts'

/** The most rows of any list the panel keeps. */
export const MAX_ROWS = 50
/** Days in the daily chart. */
export const CHART_DAYS = 30

const BAN_TOOL_STATES: readonly BanToolState[] = ['running', 'not_running', 'not_available']
const banTool = (value: unknown): BanToolState | null => BAN_TOOL_STATES.find((state) => state === value) ?? null

export function readBaseline(value: unknown): SecurityBaseline {
  const source = isRec(value) ? value : {}
  return {
    password_login: flag(source.password_login), ban_tool: banTool(source.ban_tool), firewall: flag(source.firewall),
    auto_updates: flag(source.auto_updates), starts_after_reboot: flag(source.starts_after_reboot), pending_updates: whole(source.pending_updates),
  }
}

function count(value: unknown): SecurityCount {
  const source = isRec(value) ? value : {}
  return { failed: whole(source.failed), blocked: whole(source.blocked) }
}

function windows(value: unknown): SecurityWindows {
  const source = isRec(value) ? value : {}
  return { h24: count(source.h24), d7: count(source.d7), d30: count(source.d30) }
}

/** The last 30 days at most; a day that is not a count is null, not zero. */
const daily = (value: unknown): (number | null)[] => (Array.isArray(value) ? value.slice(-CHART_DAYS).map(whole) : [])

function blockedRow(value: unknown): BlockedAddress | null {
  if (!isRec(value)) return null
  const address = clean(value.address, MAX_TEXT)
  return address === null ? null : { address, since: when(value.since), until: when(value.until), attempts: whole(value.attempts) }
}

function nameRow(value: unknown): BotName | null {
  if (!isRec(value)) return null
  const name = clean(value.name, MAX_TEXT)
  const seen = whole(value.count)
  return name === null || seen === null ? null : { name, count: seen }
}

const LOGIN_METHODS: readonly LoginMethod[] = ['key', 'password']
const method = (value: unknown): LoginMethod | null => LOGIN_METHODS.find((one) => one === value) ?? null

function loginRow(value: unknown): AcceptedLogin | null {
  if (!isRec(value)) return null
  const how = method(value.method)
  const user = clean(value.user, MAX_TEXT)
  const address = clean(value.address, MAX_TEXT)
  const times = whole(value.count)
  if (how === null || user === null || address === null || times === null) return null
  return { method: how, user, address, count: times, last_seen: when(value.last_seen) }
}

const listed = <T>(value: unknown, read: (item: unknown) => T | null): T[] => rows(value, read, MAX_ROWS)

const counts = (one: SecurityCount): (number | null)[] => [one.failed, one.blocked]

/** True when the helper told us at least one thing. An empty report is the same as no report: no fake zeros. */
function saidAnything(report: MachineSecurity): boolean {
  const known = [...Object.values(report.baseline), ...counts(report.windows.h24), ...counts(report.windows.d7), ...counts(report.windows.d30)]
  return known.some((item) => item !== null) || report.daily_failed.some((item) => item !== null) || report.blocked.length + report.logins.length + report.usernames.length > 0
}

/** The report of `Machine.security`, with anything out of shape left out; null when the machine does not report or sent nothing readable. */
export function readSecurity(value: unknown): MachineSecurity | null {
  if (!isRec(value)) return null
  const report: MachineSecurity = {
    baseline: readBaseline(value.baseline), windows: windows(value.windows), daily_failed: daily(value.daily_failed),
    blocked: listed(value.blocked, blockedRow), usernames: listed(value.usernames, nameRow), logins: listed(value.logins, loginRow),
  }
  return saidAnything(report) ? report : null
}

/** The report of one machine; null is "not reporting". */
export const securityOf = (machine: Machine): MachineSecurity | null => readSecurity(machine.security)
