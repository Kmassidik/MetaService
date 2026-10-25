// Checks the answer of GET /api/machines/{id}/storage (and of the scan route) before the Storage tab trusts it. A wrong shape throws UnreadableAnswer.
import { UnreadableAnswer } from './machineDetail.ts'
import type { MachineStorageReply, Storage, StorageKind, StorageMap, StorageNode, StorageReclaim } from './types.ts'

type Rec = Record<string, unknown>

const KINDS: readonly StorageKind[] = ['code', 'agent', 'toolchain', 'synced', 'git', 'media', 'documents', 'cache', 'vms', 'other']
const RECLAIMS: readonly StorageReclaim[] = ['regenerable', 'sync_history', 'package_store', 'build_output', 'reinstallable', 'sandbox_layers', 'snapshots', 'trash', 'temporary']
const TYPES: readonly StorageNode['type'][] = ['dir', 'file', 'rest']
const STATES: readonly MachineStorageReply['state'][] = ['online', 'offline', 'old_helper']
export const MAX_NODES = 12000

const isRec = (value: unknown): value is Rec => typeof value === 'object' && value !== null && !Array.isArray(value)

function rec(value: unknown, what: string): Rec {
  if (!isRec(value)) throw new UnreadableAnswer(`${what} is not an object`)
  return value
}

function count(source: Rec, key: string): number {
  const value = source[key]
  if (typeof value === 'number' && Number.isFinite(value)) return Math.max(0, value)
  throw new UnreadableAnswer(`${key} is not a number`)
}

function text(source: Rec, key: string): string {
  const value = source[key]
  if (typeof value === 'string') return value
  throw new UnreadableAnswer(`${key} is not text`)
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], what: string): T {
  const found = allowed.find((word) => word === value)
  if (found === undefined) throw new UnreadableAnswer(`${what} is not one the panel knows`)
  return found
}

/** A kind or a reason the panel does not know yet (a newer helper) reads as `other` or none, never as a broken answer. */
const kindOf = (value: unknown): StorageKind => KINDS.find((word) => word === value) ?? 'other'
const reclaimOf = (value: unknown): StorageReclaim | null => RECLAIMS.find((word) => word === value) ?? null

function node(value: unknown, place: number, earlier: readonly StorageNode[]): StorageNode {
  const source = rec(value, 'a storage entry')
  const parent = source.parent
  if (typeof parent !== 'number' || !Number.isInteger(parent)) throw new UnreadableAnswer('parent is not a whole number')
  if (place === 0 ? parent !== -1 : parent < 0 || parent >= place || earlier[parent]?.type !== 'dir') throw new UnreadableAnswer(`entry ${place} does not sit in an earlier folder`)
  const modified = source.modified
  return {
    parent,
    name: text(source, 'name'),
    type: oneOf(source.type, TYPES, 'type'),
    bytes: count(source, 'bytes'),
    files: count(source, 'files'),
    items: count(source, 'items'),
    kind: kindOf(source.kind),
    reclaim: reclaimOf(source.reclaim),
    modified: typeof modified === 'number' && Number.isFinite(modified) ? modified : null,
  }
}

function map(value: unknown): StorageMap {
  const source = rec(value, 'map')
  const disk = rec(source.disk, 'disk')
  const raw = source.nodes
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_NODES) throw new UnreadableAnswer('nodes is not a list of 1 to 12000 entries')
  const nodes: StorageNode[] = []
  raw.forEach((entry, place) => nodes.push(node(entry, place, nodes)))
  if (nodes[0]?.type !== 'dir') throw new UnreadableAnswer('the first entry is not a folder')
  return {
    root: text(source, 'root'),
    finished_at: text(source, 'finished_at'),
    seconds: count(source, 'seconds'),
    entries: count(source, 'entries'),
    unreadable: count(source, 'unreadable'),
    disk: { total_bytes: count(disk, 'total_bytes'), used_bytes: count(disk, 'used_bytes'), free_bytes: count(disk, 'free_bytes') },
    nodes,
  }
}

function storage(value: unknown): Storage {
  const source = rec(value, 'storage')
  if (typeof source.scanning !== 'boolean') throw new UnreadableAnswer('scanning is not true or false')
  const progress = source.progress === null || source.progress === undefined ? null : rec(source.progress, 'progress')
  const error = source.error
  return {
    scanning: source.scanning,
    progress: progress ? { entries: count(progress, 'entries'), bytes: count(progress, 'bytes') } : null,
    error: typeof error === 'string' && error ? error : null,
    map: source.map === null || source.map === undefined ? null : map(source.map),
  }
}

export function parseStorageReply(value: unknown): MachineStorageReply {
  const source = rec(value, 'answer')
  return { state: oneOf(source.state, STATES, 'state'), storage: source.storage === null || source.storage === undefined ? null : storage(source.storage) }
}
