// The plain words and small numbers the sandbox pages show: states, end times, sizes, durations and the two confirm dialogs.
// Pure: no DOM, no network, so every rule is tested without a browser.
import { formatGb, formatMb } from './format.ts'

const SECOND = 1000
const MINUTE = 60 * SECOND
const HOUR = 60 * MINUTE
const SECONDS_PER_MINUTE = 60
const SECONDS_PER_HOUR = 60 * SECONDS_PER_MINUTE
const SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR

/** The team name the Root makes for a key that names none, so a key is never left without an owner. */
export const DEFAULT_TEAM_NAME = 'Our apps'
export const TEAM_NAME_MAX = 48
export const TEAM_NAME_RULE = `Use letters, numbers, spaces and - _ . & ( ) ' only, up to ${TEAM_NAME_MAX} characters.`
const TEAM_NAME_PATTERN = /^[\p{L}\p{M}0-9 _.()'&-]+$/u
const DOUBLE_SPACE = '  '

/** An empty field means the default team; anything else must be a name the Root keeps as typed. */
export function teamNameProblem(name: string): string | null {
  if (!name.trim()) return null
  if (name !== name.trim() || name.includes(DOUBLE_SPACE)) return TEAM_NAME_RULE
  if (Array.from(name).length > TEAM_NAME_MAX) return TEAM_NAME_RULE
  return TEAM_NAME_PATTERN.test(name) ? null : TEAM_NAME_RULE
}

const STATE_LABELS: Record<string, string> = {
  starting: 'Starting',
  running: 'Running',
  pausing: 'Pausing',
  paused: 'Paused',
  resuming: 'Resuming',
  stopping: 'Stopping',
  ended: 'Ended',
}

export const sandboxStateLabel = (state: string): string => STATE_LABELS[state] ?? 'Unknown'

/** The colour of a state tag: green when it runs, amber when it is paused or on its way, plain when it has ended. */
export function sandboxStateTone(state: string): '' | 'run' | 'warn' | 'act' {
  if (state === 'running') return 'run'
  if (state === 'paused') return 'warn'
  if (state === 'starting' || state === 'resuming' || state === 'pausing' || state === 'stopping') return 'act'
  return ''
}

const span = (ms: number, unit: number): string => `${Math.max(1, Math.round(ms / unit))}`

/** How long is left before the end time: "in 4m", "in 30s", "in 1h 5m", or "any moment" once it is due. */
export function endsText(endAt: string, now: number): string {
  const at = Date.parse(endAt)
  if (Number.isNaN(at)) return 'unknown'
  const left = at - now
  if (left <= 0) return 'any moment'
  if (left < MINUTE) return `in ${span(left, SECOND)}s`
  if (left < HOUR) return `in ${span(left, MINUTE)}m`
  return `in ${Math.floor(left / HOUR)}h ${Math.floor((left % HOUR) / MINUTE)}m`
}

/** What a sandbox holds, in the panel's short words: "2 vCPU · 512 MB · 10 GB". */
export const shapeText = (vcpu: number, ramMb: number, diskMb: number): string =>
  `${vcpu} vCPU · ${formatMb(ramMb)} · ${formatGb(diskMb / 1024)}`

/** A counted number of seconds in plain words: "45s", "11m", "3h 5m", "2d 4h". */
export function durationText(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds))
  if (whole < SECONDS_PER_MINUTE) return `${whole}s`
  if (whole < SECONDS_PER_HOUR) return `${Math.floor(whole / SECONDS_PER_MINUTE)}m`
  if (whole < SECONDS_PER_DAY) return `${Math.floor(whole / SECONDS_PER_HOUR)}h ${Math.floor((whole % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)}m`
  return `${Math.floor(whole / SECONDS_PER_DAY)}d ${Math.floor((whole % SECONDS_PER_DAY) / SECONDS_PER_HOUR)}h`
}

/** A counted number with thousands marks, as the ledger shows them. */
export const countText = (value: number): string => Math.round(value).toLocaleString('en')

export const keyState = (revokedAt: string | null): 'Active' | 'Revoked' => (revokedAt ? 'Revoked' : 'Active')

export const windowLabel = (days: number): string => `Last ${days} ${days === 1 ? 'day' : 'days'}`

/** The windows the usage page offers, in days. */
export const USAGE_WINDOWS: readonly number[] = [7, 30]

export interface ConfirmCopy {
  title: string
  what: string
  consequence: string
  confirmLabel: string
}

export function killCopy(sandbox: { id: string; template: string; team_name: string }): ConfirmCopy {
  return {
    title: 'Kill this sandbox?',
    what: `Sandbox ${sandbox.id} (${sandbox.template}, team ${sandbox.team_name}) stops now.`,
    consequence: 'Everything inside it is lost: its files, its running programs and its memory. It cannot be started again.',
    confirmLabel: 'Kill sandbox',
  }
}

export function revokeCopy(key: { prefix: string; team_name: string }): ConfirmCopy {
  return {
    title: 'Revoke this key?',
    what: `The key ${key.prefix}… of team ${key.team_name} stops working now.`,
    consequence: 'Any program using it is refused from now on. A new key can be made the same way, and shown once.',
    confirmLabel: 'Revoke key',
  }
}

/** What every team used together, for the totals line under the table. */
export function usageTotals(teams: readonly { sandboxes: number; seconds: number; vcpu_seconds: number; ram_mb_seconds: number }[]) {
  return teams.reduce(
    (sum, team) => ({
      sandboxes: sum.sandboxes + team.sandboxes,
      seconds: sum.seconds + team.seconds,
      vcpu_seconds: sum.vcpu_seconds + team.vcpu_seconds,
      ram_mb_seconds: sum.ram_mb_seconds + team.ram_mb_seconds,
    }),
    { sandboxes: 0, seconds: 0, vcpu_seconds: 0, ram_mb_seconds: 0 },
  )
}
