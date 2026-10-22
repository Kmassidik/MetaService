// The SSH keys of one VM: what the panel checks before sending, how the answer is read, and the plain lines shown under the list. Pure, so every rule is tested.
import { relativeTime } from './format.ts'
import { parseSetup } from './sshSetup.ts'
import { RUNNING_STATE } from './vm.ts'
import type { SshdState, SshKey, SshKeyList } from './types.ts'

/** The most keys one VM may hold (the parent refuses the next one). */
export const MAX_SSH_KEYS = 20
const MS_PER_SECOND = 1000
const PRIVATE_KEY_MARK = 'PRIVATE KEY'
const SSHD_STATES: readonly SshdState[] = ['running', 'installed', 'missing', 'unknown']

export const HELP_LINE = 'Paste the public key (the file that ends in .pub). Never paste a private key.'
export const CONNECT_NOTE = "Works from the machine's own network, or through the machine with ssh -J. Outside access comes later."
export const REFUSAL_CODES = { duplicate: 'duplicate_key', tooMany: 'too_many_keys' } as const

const EMPTY_TEXT = 'Paste a public key first.'
const PRIVATE_KEY_TEXT = 'That looks like a private key. Never paste a private key here: paste the public key, the file that ends in .pub.'
const DUPLICATE_TEXT = 'This key is already on this VM.'
const TOO_MANY_TEXT = `This VM already has ${MAX_SSH_KEYS} keys. Remove one before adding another.`
const NOT_APPLIED_STOPPED = 'Saved. It will be written into the VM when the VM is running.'
const NOT_APPLIED_RUNNING = 'Saved, not applied yet: the machine did not answer. It will retry.'
const SSHD_MISSING = 'No SSH server was found in this VM. Keys are saved, but nobody can log in until the image runs one.'
const SSHD_INSTALLED = 'An SSH server is installed in this VM but not running.'

export type KeyCheck = { ok: true; key: string } | { ok: false; text: string }

/** What the panel sends: the pasted text without surrounding spaces (the parent refuses them), or the reason it must not be sent at all. */
export function checkPastedKey(pasted: string): KeyCheck {
  const key = pasted.trim()
  if (key === '') return { ok: false, text: EMPTY_TEXT }
  if (key.includes(PRIVATE_KEY_MARK)) return { ok: false, text: PRIVATE_KEY_TEXT }
  return { ok: true, key }
}

/** The plain words for a refusal of Add: our own for the two known codes, else what the parent said. */
export function addRefusalText(refusal: { code: string; message: string }): string {
  if (refusal.code === REFUSAL_CODES.duplicate) return DUPLICATE_TEXT
  return refusal.code === REFUSAL_CODES.tooMany ? TOO_MANY_TEXT : refusal.message
}

/** The status lines under the list, from the answer and the state of the VM. Empty when there is nothing to say, and while SSH is being set up or failed (that block says it). */
export function statusLines(list: Pick<SshKeyList, 'applied' | 'sshd' | 'sshdState'>, vmState: string): string[] {
  if (list.sshdState !== 'idle') return []
  const lines: string[] = []
  if (!list.applied) lines.push(vmState === RUNNING_STATE ? NOT_APPLIED_RUNNING : NOT_APPLIED_STOPPED)
  if (list.sshd === 'missing') lines.push(SSHD_MISSING)
  if (list.sshd === 'installed') lines.push(SSHD_INSTALLED)
  return lines
}

/** How long ago a key was added (the parent counts Unix seconds). */
export const addedText = (key: Pick<SshKey, 'added_at'>, now: number = Date.now()): string => relativeTime(new Date(key.added_at * MS_PER_SECOND).toISOString(), now)

/** The line a person copies to log in: root at the VM's address. Null while the VM has none. */
export const connectionLine = (address: string | null | undefined): string | null => (address ? `ssh root@${address}` : null)

type Fields = Record<string, unknown>

const isFields = (value: unknown): value is Fields => typeof value === 'object' && value !== null && !Array.isArray(value)

function parseKey(value: unknown): SshKey | null {
  if (!isFields(value)) return null
  const { id, type, fingerprint, comment, added_at: addedAt } = value
  if (typeof id !== 'string' || typeof type !== 'string' || typeof fingerprint !== 'string' || typeof addedAt !== 'number') return null
  return { id, type, fingerprint, comment: typeof comment === 'string' ? comment : '', added_at: addedAt }
}

const isSshdState = (value: unknown): value is SshdState => SSHD_STATES.some((state) => state === value)

/** Reads an answer of the SSH-keys routes. Null when it is not in the promised shape; a key that is not readable is dropped. */
export function parseSshKeyList(body: unknown): SshKeyList | null {
  if (!isFields(body) || !Array.isArray(body.keys)) return null
  const keys = body.keys.map(parseKey).filter((key): key is SshKey => key !== null)
  return { keys, applied: body.applied === true, sshd: isSshdState(body.sshd) ? body.sshd : 'unknown', ...parseSetup(body) }
}
