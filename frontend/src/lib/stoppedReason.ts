// Why a VM stopped by itself, and the words the panel uses for it. The reason comes from the helper, and its log lines come from inside the VM: untrusted text.
// Everything here only reads and cleans it; the pages show it as text (never as markup).
import type { Command, Workload } from './types.ts'

/** The same promise the parent keeps: the last lines, at most this many, and at most this many bytes. */
export const MAX_REASON_LINES = 12
export const MAX_REASON_BYTES = 2048

/** The longest reason a failed order may carry (the parent keeps the same promise): the last lines, at most this many, and at most this many bytes. */
export const MAX_FAILURE_LINES = 40
export const MAX_FAILURE_BYTES = 6000

export interface StoppedReason {
  /** Null when the helper could not tell. */
  exit_code: number | null
  log_tail: string
  /** Only on a reason the Root names (for example `gpu_memory_over_limit`); left out for the Mac reasons. */
  code?: string
  /** Plain words from the Root for a named reason; text only, never markup. */
  message?: string
  used_gb?: number | null
  limit_gb?: number | null
}

/** Why a stopped VM stopped: the helper's reason, the panel's own stop, or a stop nobody can explain yet. */
export type StopNote = { kind: 'reason'; reason: StoppedReason } | { kind: 'panel' } | { kind: 'own' }

export const PLAIN_MODE_TEXT = 'This VM runs without systemd (a system service manager). A terminal works; services like systemd do not.'

const STOPPED = 'stopped'
const FAILED = 'failed'
const STOP_ORDER = 'stop'
const ORDERS_THAT_CHANGE_STATE = new Set(['start', 'stop'])
const SUCCEEDED = 'succeeded'
const NOTES: Record<'panel' | 'own', string> = {
  panel: 'It was stopped.',
  own: 'It stopped on its own; the machine did not say why yet.',
}

const ESCAPE = 0x1b
const BELL = 0x07
const NEWLINE = 0x0a
const TAB = 0x09
const SPACE = ' '
const SEQUENCE_END_FIRST = 0x40
const SEQUENCE_END_LAST = 0x7e
const FIRST_CONTROL_AFTER_C0 = 0x7f
const LAST_C1_CONTROL = 0x9f
const FIRST_PRINTABLE = 0x20

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)

const isControl = (code: number): boolean => code < FIRST_PRINTABLE || (code >= FIRST_CONTROL_AFTER_C0 && code <= LAST_C1_CONTROL)

/** Without escape sequences (colours, cursor moves, window titles) and without control characters. A new line stays; a tab becomes a space. */
function plainText(raw: string): string {
  const characters = Array.from(raw)
  const kept: string[] = []
  for (let index = 0; index < characters.length; index += 1) {
    const code = characters[index]?.codePointAt(0) ?? 0
    if (code === ESCAPE) {
      index = endOfSequence(characters, index)
      continue
    }
    if (code === TAB) kept.push(SPACE)
    else if (code === NEWLINE || !isControl(code)) kept.push(characters[index] ?? '')
  }
  return kept.join('')
}

/** Where the escape sequence that starts at `start` ends (the index of its last character). */
function endOfSequence(characters: string[], start: number): number {
  const kind = characters[start + 1]
  if (kind === '[') return indexOfFirst(characters, start + 2, (code) => code >= SEQUENCE_END_FIRST && code <= SEQUENCE_END_LAST)
  if (kind === ']') return endOfTitle(characters, start + 2)
  return start + 1
}

function endOfTitle(characters: string[], from: number): number {
  const end = indexOfFirst(characters, from, (code) => code === BELL || code === ESCAPE)
  return characters[end]?.codePointAt(0) === ESCAPE ? end + 1 : end
}

function indexOfFirst(characters: string[], from: number, test: (code: number) => boolean): number {
  for (let index = from; index < characters.length; index += 1) {
    if (test(characters[index]?.codePointAt(0) ?? 0)) return index
  }
  return characters.length
}

const byteLength = (text: string): number => new TextEncoder().encode(text).length

/** The end of the text that fits in `maxBytes`, never cutting a character in half. */
function cutStart(text: string, maxBytes: number): string {
  const characters = Array.from(text)
  let size = byteLength(text)
  let first = 0
  while (size > maxBytes && first < characters.length) {
    size -= byteLength(characters[first] ?? '')
    first += 1
  }
  return characters.slice(first).join('')
}

function lastLines(raw: string, maxLines: number, maxBytes: number): string {
  const lines = plainText(raw).split('\n').filter((line) => line !== '')
  return cutStart(lines.slice(-maxLines).join('\n'), maxBytes)
}

const cleanTail = (raw: string): string => lastLines(raw, MAX_REASON_LINES, MAX_REASON_BYTES)

/** The reason a machine gave for a failed order, cleaned and capped again. It may hold the last lines a VM printed, so it is text only. */
export const cleanFailureText = (raw: string): string => lastLines(raw, MAX_FAILURE_LINES, MAX_FAILURE_BYTES)

/** The code of the reason the Root named for a VM stopped by the helper because it stayed over its GPU memory limit. */
export const GPU_OVER_LIMIT_CODE = 'gpu_memory_over_limit'
export const GPU_OVER_LIMIT_HINT = 'Its GPU memory limit is still booked. Start it again, or delete it to free the booking.'

type Fields = Record<string, unknown>

const optionalGb = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? value : null)

/** The fields only a named reason has. A reason without a code (the Mac reasons) gets none, so its shape stays as it was. */
function namedFields(value: Fields): Pick<StoppedReason, 'code' | 'message' | 'used_gb' | 'limit_gb'> | Record<string, never> {
  if (typeof value.code !== 'string') return {}
  const message = typeof value.message === 'string' ? { message: plainText(value.message) } : {}
  return { code: value.code, ...message, used_gb: optionalGb(value.used_gb), limit_gb: optionalGb(value.limit_gb) }
}

/** The exit code (null when missing for a named reason), or undefined when it is not readable. */
function readExitCode(value: Fields, named: boolean): number | null | undefined {
  const exitCode = value.exit_code
  if (exitCode === null || (named && exitCode === undefined)) return null
  return typeof exitCode === 'number' && Number.isInteger(exitCode) ? exitCode : undefined
}

/** The log tail (empty when missing for a named reason), or undefined when it is not readable. */
function readLogTail(value: Fields, named: boolean): string | undefined {
  if (typeof value.log_tail === 'string') return cleanTail(value.log_tail)
  return named && value.log_tail === undefined ? '' : undefined
}

/** The reason in the promised shape, cleaned again, or null when the value is not one. A reason with a `code` may leave out the exit code and the log. */
export function readStoppedReason(value: unknown): StoppedReason | null {
  if (!isRecord(value)) return null
  const named = typeof value.code === 'string'
  const exitCode = readExitCode(value, named)
  const tail = readLogTail(value, named)
  if (exitCode === undefined || tail === undefined) return null
  return { exit_code: exitCode, log_tail: tail, ...namedFields(value) }
}

export const exitCodeText = (code: number | null): string => (code === null ? 'The exit code is not known.' : `Exit code ${code}.`)

/** True when the machine's newest start or stop order for this VM is a stop that went through, so the panel itself stopped it. */
function stoppedByThePanel(machineId: string, workloadId: string, commands: Command[]): boolean {
  const orders = commands.filter((order) => order.machine === machineId && order.workload_id === workloadId && ORDERS_THAT_CHANGE_STATE.has(order.type) && order.state === SUCCEEDED)
  const newest = orders.reduce<Command | null>((latest, order) => (latest === null || Date.parse(order.created_at) >= Date.parse(latest.created_at) ? order : latest), null)
  return newest?.type === STOP_ORDER
}

/** What to say about a stopped VM, or null when there is nothing to say (it is not stopped, or it failed and nobody knows why). */
export function stopNote(machineId: string, workload: Workload, commands: Command[]): StopNote | null {
  const reason = readStoppedReason(workload.stopped_reason)
  if (reason && (workload.state === STOPPED || workload.state === FAILED)) return { kind: 'reason', reason }
  if (workload.state !== STOPPED) return null
  return { kind: stoppedByThePanel(machineId, workload.id, commands) ? 'panel' : 'own' }
}

/** A note for the places that only show a reason the machine gave (table rows, cards). */
export const reasonNote = (reason: StoppedReason | null): StopNote | null => (reason ? { kind: 'reason', reason } : null)

/** The sentence for a stop without a reason. */
export const stopNoteText = (note: { kind: 'panel' | 'own' }): string => NOTES[note.kind]

/** True when the VM runs without systemd (its first start with systemd did not work). */
export const isPlainMode = (workload: Pick<Workload, 'init_mode'>): boolean => workload.init_mode === 'plain'
