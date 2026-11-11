// What the panel does when the machine under a VM is offline: its buttons are off with a reason, its state is called "last known", and a refusal that says the machine did not answer is put in friendlier words.
import { STATE_LABELS } from './format.ts'
import type { Machine, MachineState } from './types.ts'

const OFFLINE_STATE: MachineState = 'offline'
/** The reason shown on a button, as a tooltip and as a small line. */
export const MACHINE_OFFLINE_REASON = 'This machine is offline.'
/** The code the parent sends when the machine did not answer a request. */
export const MACHINE_UNREACHABLE_CODE = 'machine_unreachable'
const MACHINE_UNREACHABLE_RAW = 'the machine could not be reached'
export const MACHINE_UNREACHABLE_TEXT = 'The machine did not answer. It may be offline or busy; try again in a minute.'
const LAST_KNOWN_SUFFIX = ' (last known)'
/** A VM being deleted keeps its own words; the state is not a stale guess. */
const OWN_WORDS_STATES = new Set(['deleting', 'Deleting…'])

export const isMachineOffline = (state: MachineState | undefined): boolean => state === OFFLINE_STATE

/** A pending card says Checking, but stays asleep and keeps the raw offline state for action guards. */
export function machineCardDisplay(machine: Pick<Machine, 'state' | 'state_pending'>): { label: string; awake: boolean; offline: boolean } {
  const pending = machine.state_pending === true
  return {
    label: pending ? 'Checking…' : (STATE_LABELS[machine.state] ?? 'Unknown'),
    awake: !pending && !isMachineOffline(machine.state),
    offline: !pending && isMachineOffline(machine.state),
  }
}

/** The refusal's words for the screen: the friendly text when the machine did not answer, else the Root's own message. */
export function refusalMessage(code: string | undefined, message: string): string {
  if (code === MACHINE_UNREACHABLE_CODE) return MACHINE_UNREACHABLE_TEXT
  return message.trim().toLowerCase().replace(/\.$/, '') === MACHINE_UNREACHABLE_RAW ? MACHINE_UNREACHABLE_TEXT : message
}

/** A VM's state words, with "(last known)" added when its machine is offline and cannot confirm them. */
export function stateWords(words: string, machineState: MachineState | undefined): string {
  if (!isMachineOffline(machineState) || OWN_WORDS_STATES.has(words)) return words
  return `${words}${LAST_KNOWN_SUFFIX}`
}

/** The tag's colour class for a VM state: none on an offline machine, because the state is only the last one heard. */
export const stateClass = (cls: string | undefined, machineState: MachineState | undefined): string => (isMachineOffline(machineState) ? '' : (cls ?? ''))
