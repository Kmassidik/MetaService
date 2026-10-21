// What the terminal window says, in plain words, when it cannot open or when it ended. Pure rules: no DOM, no network.
// The window itself is components/Terminal.svelte; the reason a VM stopped comes from lib/stoppedReason.ts.
import { STOPPED_STATE } from './vm.ts'

/** A shell that ends within this long of opening means the VM itself stopped right after it started. */
export const QUICK_END_MS = 5000

/** How the terminal ended: the parent refused to open it (with its error code), or the socket closed (with the parent's reason and how long it had been open). */
export type Ending = { kind: 'refused'; code: string } | { kind: 'closed'; reason: string; openMs: number }

export interface Notice {
  text: string
  /** Show why the VM stopped (its reason, or the sentence about a stop nobody can explain). */
  why: boolean
  /** Offer the Start button: the VM is known to be stopped. */
  canStart: boolean
}

/** The words after the dot while the window explains why there is no terminal, instead of an "error" the person cannot use. */
export const NOTICE_STATUS = 'not connected'

/** While Start is working the window asks the parent for the VM's state this often, and gives up after this long. */
export const START_POLL_MS = 3000
export const START_GIVE_UP_MS = 90_000

const SHELL_ENDED = 'the shell ended'
const VM_STOPPED = 'the VM stopped'
const VM_DELETED = 'the VM was deleted'
const MACHINE_OFFLINE = 'the machine is offline'

const REFUSALS = new Map([
  ['not_supported', 'Terminals work on Mac machines only for now.'],
  ['unreachable', 'The machine is offline, so this VM cannot be reached right now.'],
  ['too_many_consoles', 'Too many terminals are open. Close one and try again.'],
  ['console_open', 'This VM already has a terminal open. Close it and try again.'],
])

const plain = (text: string): Notice => ({ text, why: false, canStart: false })
const stopped = (text: string, vmState: string | null): Notice => ({ text, why: true, canStart: vmState === STOPPED_STATE })

function refusedNotice(code: string, vmState: string | null): Notice | null {
  const known = REFUSALS.get(code)
  if (code !== 'not_running') return known === undefined ? null : plain(known)
  if (vmState === STOPPED_STATE) return stopped('This VM has stopped, so there is nothing to connect to.', vmState)
  return plain('This VM is not running right now, so there is nothing to connect to.')
}

function closedNotice(reason: string, openMs: number, vmState: string | null): Notice | null {
  if (reason === VM_DELETED) return plain('This VM was deleted.')
  if (reason === MACHINE_OFFLINE) return plain('The machine went offline, so the terminal was closed.')
  const vmIsDown = reason === VM_STOPPED || vmState === STOPPED_STATE
  if (openMs < QUICK_END_MS && (vmIsDown || reason === SHELL_ENDED)) return stopped('The VM stopped right after it started.', vmState)
  return vmIsDown ? stopped('This VM has stopped.', vmState) : null
}

/** The message to show in the window instead of the bare status line, or null when the status line says it well enough. `vmState` is null when the VM is not in the list. */
export function terminalNotice(ending: Ending | null, vmState: string | null): Notice | null {
  if (!ending) return null
  return ending.kind === 'refused' ? refusedNotice(ending.code, vmState) : closedNotice(ending.reason, ending.openMs, vmState)
}
