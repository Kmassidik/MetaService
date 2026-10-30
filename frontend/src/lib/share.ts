// Read the Share a PC answers (the hub's, passed through by the parent) before the panel trusts them.
// Anything that is not the promised shape throws UnreadableAnswer; it is never treated as an empty list.
import { isFields, UnreadableAnswer, type Fields } from './unreadable.ts'

export const SHARE_OSES = ['mac', 'windows', 'linux'] as const
export const SHARE_CPUS = ['arm64', 'x86_64'] as const
export const BUILD_STATES = ['ready', 'untested', 'missing', 'soon'] as const

export type ShareOs = (typeof SHARE_OSES)[number]
export type ShareCpu = (typeof SHARE_CPUS)[number]
export type BuildState = (typeof BUILD_STATES)[number]

export interface CpuChoice {
  cpu: ShareCpu
  state: BuildState
}

export interface OsChoice {
  os: ShareOs
  cpus: CpuChoice[]
}

export interface Share {
  cores: number
  ram_mb: number
  disk_gb: number
}

export interface PendingMachine {
  id: string
  /** Typed by a far PC: only ever shown as text. */
  hostname: string
  os: ShareOs
  cpu: ShareCpu
  /** What the machine asked to share. */
  share: Share
  expiresAt: string
  triesLeft: number
}

export interface JoinedMachine {
  name: string
  address: string
  /** The first characters of the WireGuard key. */
  key: string
  os: ShareOs
  cpu: ShareCpu
  /** Seconds since the last handshake, null when there never was one. */
  handshakeSecsAgo: number | null
}

export interface JoinCommand {
  command: string
  expiresAt: string
}

function text(source: Fields, key: string): string {
  const value = source[key]
  if (typeof value !== 'string') throw new UnreadableAnswer(`${key} is not text`)
  return value
}

function whole(source: Fields, key: string, least: number): number {
  const value = source[key]
  if (typeof value !== 'number' || !Number.isInteger(value) || value < least) throw new UnreadableAnswer(`${key} is not a whole number from ${least}`)
  return value
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], what: string): T {
  const found = allowed.find((word) => word === value)
  if (found === undefined) throw new UnreadableAnswer(`${what} is not one the panel knows`)
  return found
}

function fields(value: unknown, what: string): Fields {
  if (!isFields(value)) throw new UnreadableAnswer(`${what} is not an object`)
  return value
}

function list(raw: unknown, what: string): unknown[] {
  if (!Array.isArray(raw)) throw new UnreadableAnswer(`${what} is not a list`)
  return raw
}

function cpuChoice(value: unknown): CpuChoice {
  const row = fields(value, 'a CPU choice')
  return { cpu: oneOf(row.cpu, SHARE_CPUS, 'cpu'), state: oneOf(row.state, BUILD_STATES, 'state') }
}

function osChoice(value: unknown): OsChoice {
  const row = fields(value, 'a system')
  return { os: oneOf(row.os, SHARE_OSES, 'os'), cpus: list(row.cpus, 'cpus').map(cpuChoice) }
}

/** The three buttons and their CPU choices (GET /api/join-share/supported). */
export const parseSupported = (raw: unknown): OsChoice[] => list(raw, 'the supported answer').map(osChoice)

function share(value: unknown): Share {
  const row = fields(value, 'share')
  return { cores: whole(row, 'cores', 1), ram_mb: whole(row, 'ram_mb', 1), disk_gb: whole(row, 'disk_gb', 1) }
}

function pendingMachine(value: unknown): PendingMachine {
  const row = fields(value, 'a waiting machine')
  return {
    id: text(row, 'id'),
    hostname: text(row, 'hostname'),
    os: oneOf(row.os, SHARE_OSES, 'os'),
    cpu: oneOf(row.cpu, SHARE_CPUS, 'cpu'),
    share: share(row.share),
    expiresAt: text(row, 'expires_at'),
    triesLeft: whole(row, 'tries_left', 0),
  }
}

/** The machines waiting for a code (GET /api/join-share/pending). */
export const parsePending = (raw: unknown): PendingMachine[] => list(raw, 'the pending answer').map(pendingMachine)

function handshake(row: Fields): number | null {
  if (row.last_handshake_secs_ago === null) return null
  return whole(row, 'last_handshake_secs_ago', 0)
}

function joinedMachine(value: unknown): JoinedMachine {
  const row = fields(value, 'a joined machine')
  return {
    name: text(row, 'name'),
    address: text(row, 'address'),
    key: text(row, 'public_key'),
    os: oneOf(row.os, SHARE_OSES, 'os'),
    cpu: oneOf(row.cpu, SHARE_CPUS, 'cpu'),
    handshakeSecsAgo: handshake(row),
  }
}

/** The machines that have joined (GET /api/join-share/peers). */
export const parsePeers = (raw: unknown): JoinedMachine[] => list(raw, 'the peers answer').map(joinedMachine)

/** The command the hub made for a far PC (POST /api/join-share/links). The command is the hub's: the panel never builds one. */
export function parseJoinCommand(raw: unknown): JoinCommand {
  const row = fields(raw, 'the link answer')
  return { command: text(row, 'command'), expiresAt: text(row, 'expires_at') }
}
