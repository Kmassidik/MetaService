// The words of the Share a PC page: names, the state of each build, times, and the remove question. Pure, so the wording is tested.
import type { BuildState, CpuChoice, JoinedMachine, OsChoice, ShareCpu, ShareOs } from './share.ts'
import type { ConfirmCopy } from './confirmCopy.ts'
import type { LogoName } from './logos.ts'

export const OS_NAMES: Record<ShareOs, string> = { mac: 'Mac', windows: 'Windows', linux: 'Linux' }
/** The logo of each system (files in assets/logos). */
export const OS_LOGOS: Record<ShareOs, LogoName> = { mac: 'apple', windows: 'windows', linux: 'linux' }
export const CPU_NAMES: Record<ShareCpu, string> = { arm64: 'Apple silicon / ARM (arm64)', x86_64: 'Intel / AMD (x86_64)' }

export interface StateText {
  tag: string
  /** The tag's colour: green, amber or the plain one. */
  tone: 'run' | 'warn' | ''
  /** One line that says what the state means. Empty when nothing needs saying. */
  why: string
}

const STATE_TEXT: Record<BuildState, StateText> = {
  ready: { tag: 'ready', tone: 'run', why: '' },
  untested: { tag: 'not tested yet', tone: 'warn', why: 'A build exists but has not been proven on this kind of computer yet. It may not work.' },
  missing: { tag: 'no build yet', tone: '', why: 'There is no helper build for this computer yet.' },
  soon: { tag: 'coming soon', tone: '', why: 'This system is coming soon.' },
}

export const stateText = (state: BuildState): StateText => STATE_TEXT[state]

/** A computer with no build, or one that is only coming, cannot be chosen. */
export const choosable = (state: BuildState): boolean => state === 'ready' || state === 'untested'

export const NO_SYSTEM_NOTE = 'Choose a system first.'

/** The line under the CPU choices: what the chosen one means, else why the others cannot be chosen. */
export function cpuNote(row: OsChoice | undefined, chosen: ShareCpu | ''): string {
  if (!row) return NO_SYSTEM_NOTE
  const picked = row.cpus.find((entry: CpuChoice) => entry.cpu === chosen)
  if (picked) return stateText(picked.state).why
  const blocked = row.cpus.filter((entry) => !choosable(entry.state))
  const first = blocked[0]
  if (!first) return ''
  return `${blocked.map((entry) => CPU_NAMES[entry.cpu]).join(' and ')}: ${stateText(first.state).why}`
}

const SECOND_LIMIT = 90
const SECONDS_IN_MINUTE = 60
const MINUTE_LIMIT = 5400
const SECONDS_IN_HOUR = 3600

/** How long a request or link still lives: "42 s left", "12 min left", "expired", or empty when the time is unreadable. */
export function timeLeft(iso: string, now: number): string {
  const seconds = Math.round((Date.parse(iso) - now) / 1000)
  if (!Number.isFinite(seconds)) return ''
  if (seconds <= 0) return 'expired'
  return seconds < SECOND_LIMIT ? `${seconds} s left` : `${Math.round(seconds / SECONDS_IN_MINUTE)} min left`
}

/** The last handshake of a joined machine, in words. */
export function handshakeText(secondsAgo: JoinedMachine['handshakeSecsAgo']): string {
  if (secondsAgo === null) return 'never'
  if (secondsAgo < SECOND_LIMIT) return `${secondsAgo} s ago`
  return secondsAgo < MINUTE_LIMIT ? `${Math.round(secondsAgo / SECONDS_IN_MINUTE)} min ago` : `${Math.round(secondsAgo / SECONDS_IN_HOUR)} h ago`
}

const FALLBACK_NAME = 'far-pc'

/** The name offered for a new machine: its host name made safe (letters, digits, dot, dash, underscore). */
export function saneName(hostname: string): string {
  const name = hostname.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '')
  return name || FALLBACK_NAME
}

/** The line that undoes a join on the computer itself. It asks for sudo once there, stops the helper and WireGuard, removes the boot entries and deletes the join folder. */
export const LEAVE_COMMAND = 'sh ~/.metaservice-join/leave.sh'

/** What a join gives and does not give, told on the page where machines join. The tunnel is outbound: the joined computer can reach the panel, and the panel can reach its helper — nothing else on that computer is exposed, and nobody else is on the mesh. */
export const MESH_NOTE =
  'A joined computer is on the shared network: the panel can reach its helper (updates, cleaning, VMs), and you can open its terminal from anywhere on this page. Its screen and its own SSH login are not exposed to the internet.'

/** What Remove here does not do: the other computer is not touched, so its helper and WireGuard keep running until someone there runs the leave command. */
export const LEAVE_NOTE = `Removing it here does not change that computer: its helper and WireGuard keep running there until someone on it runs ${LEAVE_COMMAND} (it asks for sudo once, stops the services and deletes the join folder).`

export const removePeerCopy = (peer: Pick<JoinedMachine, 'name'>, cleaning = false): ConfirmCopy => ({
  title: 'Remove this machine?',
  what: `${peer.name} will be taken out of the shared network.`,
  consequence: cleaning
    ? 'The computer is cleaned first (its helper, WireGuard, boot entries and join folder), then its address is freed and it is taken out of the list. The person can join again with a new command.'
    : `Its address is freed and it can no longer reach the parent. ${LEAVE_NOTE} The person can join again with a new command.`,
  confirmLabel: 'Remove machine',
  busyLabel: 'Removing…',
  doneLabel: 'Removed',
})
