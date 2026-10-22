// The SSH keys the stand-in Root holds for each VM, and the rules the parent applies to a pasted line. Fingerprints are computed from the key blob, so a key always gets the same SHA256:... name.
import { createHash } from 'node:crypto'

const MAX_KEYS = 20
const KEY_TYPE_PREFIXES = ['ssh-', 'ecdsa-', 'sk-']
const FIRST_KEY_TIME = 1_700_000_000

export type SshdReport = 'running' | 'installed' | 'missing' | 'unknown'

export interface StoredKey {
  id: string
  type: string
  fingerprint: string
  comment: string
  added_at: number
}

export type SetupProgress = 'idle' | 'installing' | 'failed'

/** Where the helper is with installing the SSH server of one VM; `left` is how many more GETs still see it installing. */
interface Setup {
  state: SetupProgress
  left: number
}

export interface BookAnswer {
  status: number
  body: Record<string, unknown>
}

export interface SshKeyBook {
  /** Every request that arrived, as "GET vm1", "POST vm1" or "DELETE vm1", in order. */
  requests: string[]
  /** What the answers say about the VM: written into it yet, and whether an SSH server was found. */
  applied: boolean
  sshd: SshdReport
  /** How long every answer takes. */
  delayMs: number
  /** How many GETs after an add or a retry still see `installing` (the answer of the add itself says installing too when this is above 0). */
  installPolls: number
  /** When set, an install ends as `failed` with this message instead of idle. */
  failure: string | null
  /** The machine's ssh_jump setting, and the office address used when it is empty (null: none). */
  jumpSetting: string | null
  officeJump: string | null
  /** True while the VMs have no address, so no command can be built. */
  addressless: boolean
  /** True to answer like the old parent: no sshd_state, no connect. */
  oldParent: boolean
  list: (vm: string) => BookAnswer
  add: (vm: string, body: Record<string, unknown>) => BookAnswer
  remove: (vm: string, id: string) => BookAnswer
  /** The retry route: starts the install again. */
  retry: (vm: string) => BookAnswer
  /** Puts a VM in a setup state without a request (a failure to start from, for example). */
  force: (vm: string, state: SetupProgress, left?: number) => void
  /** Puts a key in without a request, for a test that needs a list to start from. */
  seed: (vm: string, line: string) => void
  reset: () => void
}

const plain = (status: number, error: string): BookAnswer => ({ status, body: { error } })
const coded = (status: number, code: string, message: string): BookAnswer => ({ status, body: { error: { code, message } } })

/** The same name ssh-keygen -l gives: SHA256 of the blob, base64 without padding. */
const fingerprintOf = (blob: string): string => `SHA256:${createHash('sha256').update(Buffer.from(blob, 'base64')).digest('base64').replace(/=+$/, '')}`

/** The line split into type, blob and comment, or the plain reason the parent refuses it. */
function parseLine(line: string): { key: Omit<StoredKey, 'id' | 'added_at'> } | { refusal: string } {
  if (line !== line.trim()) return { refusal: 'The key has spaces or line breaks around it.' }
  if (line.includes('\n') || line.includes('\r')) return { refusal: 'Paste one key on one line.' }
  if (line.startsWith('command=') || line.startsWith('from=') || line.startsWith('no-')) return { refusal: 'Keys with options in front are not accepted. Paste only the key.' }
  const [type = '', blob = '', ...comment] = line.split(/\s+/)
  if (!KEY_TYPE_PREFIXES.some((prefix) => type.startsWith(prefix)) || blob === '') return { refusal: 'That is not a public key. It should start with ssh-ed25519, ssh-rsa or ecdsa-.' }
  return { key: { type, fingerprint: fingerprintOf(blob), comment: comment.join(' ') } }
}

const NO_POLLS = 0
const MIN_RETRY_POLLS = 1
const DEFAULTS = { applied: true, sshd: 'running', delayMs: 0, installPolls: NO_POLLS, failure: null, jumpSetting: null, officeJump: 'luca@202.0.113.9', addressless: false, oldParent: false } as const

/** The private address the stand-in gives each VM: vm1 is 10.0.0.1 (the same rule as its machine list). */
const addressOf = (vm: string): string => `10.0.0.${vm.replace(/\D/g, '')}`

export function createSshKeyBook(): SshKeyBook {
  const keys = new Map<string, StoredKey[]>()
  const setups = new Map<string, Setup>()
  let counter = 0
  const book: SshKeyBook = {
    requests: [],
    ...DEFAULTS,
    list(vm) {
      book.requests.push(`GET ${vm}`)
      advance(vm)
      return answer(vm)
    },
    add(vm, body) {
      book.requests.push(`POST ${vm}`)
      const line = typeof body.public_key === 'string' ? body.public_key : ''
      const parsed = parseLine(line)
      if ('refusal' in parsed) return plain(400, parsed.refusal)
      const held = keys.get(vm) ?? []
      if (held.some((entry) => entry.fingerprint === parsed.key.fingerprint)) return coded(409, 'duplicate_key', 'That key is already on this VM.')
      if (held.length >= MAX_KEYS) return coded(409, 'too_many_keys', 'This VM already has 20 keys.')
      keys.set(vm, [...held, stored(parsed.key)])
      begin(vm, book.installPolls)
      return { status: 201, body: answer(vm).body }
    },
    remove(vm, id) {
      book.requests.push(`DELETE ${vm}`)
      const held = keys.get(vm) ?? []
      if (!held.some((entry) => entry.id === id)) return coded(404, 'not_found', 'No such key.')
      keys.set(vm, held.filter((entry) => entry.id !== id))
      return answer(vm)
    },
    retry(vm) {
      book.requests.push(`RETRY ${vm}`)
      begin(vm, Math.max(book.installPolls, MIN_RETRY_POLLS))
      return answer(vm)
    },
    force(vm, state, left = NO_POLLS) {
      setups.set(vm, { state, left })
    },
    seed(vm, line) {
      const parsed = parseLine(line)
      if ('refusal' in parsed) throw new Error(`bad seed key: ${parsed.refusal}`)
      keys.set(vm, [...(keys.get(vm) ?? []), stored(parsed.key)])
    },
    reset() {
      keys.clear()
      setups.clear()
      counter = 0
      Object.assign(book, { requests: [], ...DEFAULTS })
    },
  }

  function stored(key: Omit<StoredKey, 'id' | 'added_at'>): StoredKey {
    counter += 1
    return { ...key, id: `key-${counter}`, added_at: FIRST_KEY_TIME + counter }
  }

  /** An add or a retry starts the install; with no polls to wait for it is over at once. */
  function begin(vm: string, polls: number): void {
    setups.set(vm, { state: 'installing', left: polls })
    if (polls === NO_POLLS) finish(vm)
  }

  function finish(vm: string): void {
    setups.set(vm, { state: book.failure === null ? 'idle' : 'failed', left: NO_POLLS })
  }

  /** Every GET while installing uses up one poll; when none is left the install ends. */
  function advance(vm: string): void {
    const setup = setups.get(vm)
    if (setup?.state !== 'installing') return
    if (setup.left > NO_POLLS) setup.left -= 1
    else finish(vm)
  }

  /** What the parent says about logging in: the jump host (the setting, else the office address) and the command built from it. */
  function connectOf(vm: string): Record<string, unknown> {
    const jump = book.jumpSetting ?? book.officeJump
    const vmAddress = book.addressless ? null : addressOf(vm)
    const command = jump !== null && vmAddress !== null ? `ssh -J ${jump} root@${vmAddress}` : null
    return { jump, jump_is_default: book.jumpSetting === null && jump !== null, vm_address: vmAddress, command }
  }

  function answer(vm: string): BookAnswer {
    const base = { keys: keys.get(vm) ?? [], applied: book.applied, sshd: book.sshd }
    if (book.oldParent) return { status: 200, body: base }
    const setup = setups.get(vm) ?? { state: 'idle', left: NO_POLLS }
    const message = setup.state === 'failed' ? book.failure : null
    return { status: 200, body: { ...base, sshd_state: setup.state, sshd_message: message, connect: connectOf(vm) } }
  }

  return book
}
