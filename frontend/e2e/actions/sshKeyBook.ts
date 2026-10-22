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
  list: (vm: string) => BookAnswer
  add: (vm: string, body: Record<string, unknown>) => BookAnswer
  remove: (vm: string, id: string) => BookAnswer
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

export function createSshKeyBook(): SshKeyBook {
  const keys = new Map<string, StoredKey[]>()
  let counter = 0
  const book: SshKeyBook = {
    requests: [],
    applied: true,
    sshd: 'running',
    delayMs: 0,
    list(vm) {
      book.requests.push(`GET ${vm}`)
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
      return { status: 201, body: answer(vm).body }
    },
    remove(vm, id) {
      book.requests.push(`DELETE ${vm}`)
      const held = keys.get(vm) ?? []
      if (!held.some((entry) => entry.id === id)) return coded(404, 'not_found', 'No such key.')
      keys.set(vm, held.filter((entry) => entry.id !== id))
      return answer(vm)
    },
    seed(vm, line) {
      const parsed = parseLine(line)
      if ('refusal' in parsed) throw new Error(`bad seed key: ${parsed.refusal}`)
      keys.set(vm, [...(keys.get(vm) ?? []), stored(parsed.key)])
    },
    reset() {
      keys.clear()
      counter = 0
      Object.assign(book, { requests: [], applied: true, sshd: 'running', delayMs: 0 })
    },
  }

  function stored(key: Omit<StoredKey, 'id' | 'added_at'>): StoredKey {
    counter += 1
    return { ...key, id: `key-${counter}`, added_at: FIRST_KEY_TIME + counter }
  }

  function answer(vm: string): BookAnswer {
    return { status: 200, body: { keys: keys.get(vm) ?? [], applied: book.applied, sshd: book.sshd } }
  }

  return book
}
