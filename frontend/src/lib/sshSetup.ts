// The "set up SSH inside the VM" part of the SSH keys answer: how the new fields are read, when the dialog asks again, and which block it shows. Pure, so every rule is tested.
import { RUNNING_STATE } from './vm.ts'
import type { SshConnect, SshdProgress, SshKeyList } from './types.ts'

/** How often the dialog asks again while the helper sets SSH up. */
export const SSH_POLL_MS = 3000

const PROGRESS_STATES: readonly SshdProgress[] = ['idle', 'installing', 'failed']

export const INSTALLING_TEXT = 'Setting up SSH inside the VM… this takes about a minute the first time.'
export const READY_TEXT = 'Ready. This key can log in.'
export const PASTE_NOTE = "Paste this in your terminal. It goes through the machine, because the VM's address is private."
export const DEFAULT_JUMP_NOTE = "Uses the machine's office address. From outside the office, set the machine's SSH address in Environment."
export const NO_VM_ADDRESS_TEXT = 'The VM has no address yet. Start it and wait a moment.'
export const NO_JUMP_TEXT = 'This machine has no SSH address yet. Set one in Environment.'
export const FAILED_FALLBACK_TEXT = 'SSH could not be set up inside the VM.'
export const ENVIRONMENT_LINK_TEXT = 'Open Environment'

/** What the dialog shows under the key list, in the order it decides. */
export type SetupBlock =
  | { kind: 'none' }
  /** An old parent sent no `connect`: only the plain `ssh root@<address>` line can be shown. */
  | { kind: 'legacy' }
  | { kind: 'installing' }
  | { kind: 'failed'; message: string }
  | { kind: 'ready'; command: string; jumpIsDefault: boolean }
  /** Ready, but there is no command to give; `needsEnvironment` says the fix is the machine's SSH address. */
  | { kind: 'no-command'; text: string; needsEnvironment: boolean }

type Fields = Record<string, unknown>

const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)
const textOrNull = (value: unknown): string | null => (typeof value === 'string' && value !== '' ? value : null)

/** Unknown or missing means idle. */
export function parseProgress(value: unknown): SshdProgress {
  return PROGRESS_STATES.find((state) => state === value) ?? 'idle'
}

/** The `connect` object, or null when it is missing or not an object (an old parent). */
export function parseConnect(value: unknown): SshConnect | null {
  if (!isFields(value)) return null
  return { jump: textOrNull(value.jump), jumpIsDefault: value.jump_is_default === true, vmAddress: textOrNull(value.vm_address), command: textOrNull(value.command) }
}

/** The fields the setup adds to an answer of the SSH-keys routes. */
export function parseSetup(body: Fields): Pick<SshKeyList, 'sshdState' | 'sshdMessage' | 'connect'> {
  return { sshdState: parseProgress(body.sshd_state), sshdMessage: textOrNull(body.sshd_message), connect: parseConnect(body.connect) }
}

/** The dialog asks again only while the helper is installing. */
export const shouldPoll = (list: Pick<SshKeyList, 'sshdState'> | null): boolean => list?.sshdState === 'installing'

const isReady = (list: SshKeyList): boolean => list.keys.length > 0 && list.applied && list.sshd === 'running' && list.sshdState === 'idle'

function readyBlock(connect: SshConnect): SetupBlock {
  if (connect.command !== null) return { kind: 'ready', command: connect.command, jumpIsDefault: connect.jumpIsDefault }
  if (connect.vmAddress === null) return { kind: 'no-command', text: NO_VM_ADDRESS_TEXT, needsEnvironment: false }
  return { kind: 'no-command', text: NO_JUMP_TEXT, needsEnvironment: true }
}

/** Which block to show for an answer. `vmState` keeps Ready from showing while the VM is not running. */
export function setupBlock(list: SshKeyList | null, vmState: string): SetupBlock {
  if (list === null) return { kind: 'none' }
  if (list.sshdState === 'installing') return { kind: 'installing' }
  if (list.sshdState === 'failed') return { kind: 'failed', message: list.sshdMessage ?? FAILED_FALLBACK_TEXT }
  if (list.connect === null) return { kind: 'legacy' }
  return isReady(list) && vmState === RUNNING_STATE ? readyBlock(list.connect) : { kind: 'none' }
}
