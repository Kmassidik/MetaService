// What a long action (an order the parent gave a machine) is doing or how it ended, in plain words. Pure: no DOM, no clock of its own.
// States: queued and running are open; succeeded, failed, timed_out and lost_contact are final. The step is one of the parent's fixed phrases
// ("Checking the machine", "Backing up ...", "Done"); it arrives as unchecked JSON, so stepOf() reads it and anything else is unknown (null).
import { cleanFailureText } from './stoppedReason.ts'
import type { Command } from './types.ts'

export const OPEN_STATES: ReadonlySet<string> = new Set(['queued', 'running'])
/** The final states in which the action did not finish its work. */
export const STOPPED_STATES: ReadonlySet<string> = new Set(['failed', 'timed_out', 'lost_contact'])
/** Orders that can be sent again without harm. Never Create: a second one would make a second machine. */
export const RETRY_TYPES = ['delete', 'start', 'stop'] as const
export type RetryType = (typeof RETRY_TYPES)[number]

/** The longest step or reason shown, in characters. The parent's longest phrase is 56. */
export const STEP_MAX_CHARS = 120
export const REASON_MAX_CHARS = 300
/** A stopped order stays on its VM this long (the Activity list keeps it longer). */
export const STOPPED_SHOWN_MS = 24 * 60 * 60 * 1000

export const WAITING_STEP = 'Waiting for the machine'
export const TIMED_OUT_TEXT = 'This took too long. Nothing more was done. Check the machine.'
export const LOST_CONTACT_TEXT = 'The machine stopped answering.'
const OTHER_FAILED_TEXT = 'The machine could not finish this.'
const FAILED_TEXTS: Record<RetryType, string> = { delete: 'The VM could not be deleted.', start: 'The VM could not be started.', stop: 'The VM could not be stopped.' }

export const isOpenState = (state: string): boolean => OPEN_STATES.has(state)
export const isStoppedState = (state: string): boolean => STOPPED_STATES.has(state)
export const isRetryType = (type: string): type is RetryType => RETRY_TYPES.some((known) => known === type)

/** Text of one line: control characters and colour codes gone, white space made one space, cut to `max` characters. */
export function oneLine(raw: string, max: number): string {
  const flat = cleanFailureText(raw).replace(/\s+/g, ' ').trim()
  const characters = Array.from(flat)
  return characters.length > max ? `${characters.slice(0, max - 1).join('')}…` : flat
}

/** The job's current step as safe plain text, or null when the order carries none or something that is not text. */
export function stepOf(command: Pick<Command, 'step'>): string | null {
  const step: unknown = command.step
  if (typeof step !== 'string') return null
  return oneLine(step, STEP_MAX_CHARS) || null
}

/** The reason the parent wrote for a failed, timed out or lost order, as one safe line; null when there is none. */
export function reasonOf(command: Pick<Command, 'result'>): string | null {
  const error: unknown = command.result?.error
  if (typeof error !== 'string') return null
  return oneLine(error, REASON_MAX_CHARS) || null
}

function lostContactText(step: string | null): string {
  return step === null ? LOST_CONTACT_TEXT : `${LOST_CONTACT_TEXT} The last step was ${step}.`
}

/** How a stopped order ended, in plain words. The parent's own reason wins; the fixed words are the fallback. */
export function stoppedText(command: Command): string {
  const reason = reasonOf(command)
  if (reason !== null) return reason
  if (command.state === 'timed_out') return TIMED_OUT_TEXT
  if (command.state === 'lost_contact') return lostContactText(stepOf(command))
  return isRetryType(command.type) ? FAILED_TEXTS[command.type] : OTHER_FAILED_TEXT
}

/** What the row of a VM says about its newest order. */
export interface JobLine {
  kind: 'working' | 'stopped'
  /** The order the line is about. */
  type: RetryType
  text: string
  /** The order to offer again, or null (a Create is never offered again). */
  retry: RetryType | null
}

function newest(orders: Command[], machine: string, workload: string): Command | null {
  const own = orders.filter((order) => order.machine === machine && order.workload_id === workload && isRetryType(order.type))
  return own.reduce<Command | null>((latest, order) => (latest === null || Date.parse(order.created_at) >= Date.parse(latest.created_at) ? order : latest), null)
}

function ageMs(order: Command, now: number): number {
  const ended = Date.parse(order.finished_at ?? order.created_at)
  return Number.isNaN(ended) ? 0 : now - ended
}

/** The line for one VM: the current step while its newest order runs, or how that order ended when it did not finish. A newer order (a retry) replaces an old one. */
export function jobLine(orders: Command[], machine: string, workload: string, now: number): JobLine | null {
  const order = newest(orders, machine, workload)
  if (order === null) return null
  if (!isRetryType(order.type)) return null
  if (isOpenState(order.state)) return { kind: 'working', type: order.type, text: stepOf(order) ?? WAITING_STEP, retry: null }
  if (!isStoppedState(order.state) || ageMs(order, now) > STOPPED_SHOWN_MS) return null
  return { kind: 'stopped', type: order.type, text: stoppedText(order), retry: order.type }
}

const STATE_WORDS: Record<string, string> = { queued: 'waiting', running: 'working', succeeded: 'done', failed: 'failed', timed_out: 'timed out', lost_contact: 'lost contact' }

/** The state as a short plain word for a list; a state the panel does not know is shown as it came, cleaned. */
export const stateWords = (state: string): string => STATE_WORDS[state] ?? oneLine(state, STEP_MAX_CHARS)
