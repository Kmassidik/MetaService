// The parts of GET /api/machines/{id} that the machine list does not carry, checked before the page trusts them.
import { parseHelperUpdate } from './helperUpdate.ts'
import { isFields as isRecord, optionalText as optionalString, UnreadableAnswer } from './unreadable.ts'
import type { Engine, HelperUpdateInfo, Ruvio, RuvioState } from './types.ts'

export { UnreadableAnswer }

export interface MachineExtras {
  agent_version: string | null
  /** The SHA-256 of the helper's program file; null for a helper that does not say. */
  agent_build: string | null
  /** Whether a newer helper can be put on this machine; absent when the parent is too old to say. */
  update?: HelperUpdateInfo
  engine: Engine | null
  box: string | null
  agent_port: number | null
  ruvio: Ruvio | null
}

const RUVIO_STATES: readonly RuvioState[] = ['unavailable', 'off', 'on', 'outdated', 'installing', 'removing']

function optionalCount(source: Record<string, unknown>, key: string): number | null {
  const value = source[key]
  if (value === null || value === undefined) return null
  if (typeof value === 'number' && Number.isInteger(value)) return value
  throw new UnreadableAnswer(`${key} is not a whole number`)
}

function parseEngine(value: unknown): Engine | null {
  if (value === null || value === undefined) return null
  if (!isRecord(value) || typeof value.name !== 'string' || typeof value.ready !== 'boolean') throw new UnreadableAnswer('engine is not readable')
  return { name: value.name, version: optionalString(value, 'version'), ready: value.ready }
}

function parseRuvio(value: unknown): Ruvio | null {
  if (value === null || value === undefined) return null
  if (!isRecord(value)) throw new UnreadableAnswer('ruvio is not readable')
  const state = RUVIO_STATES.find((known) => known === value.state)
  if (!state) throw new UnreadableAnswer('ruvio has an unknown state')
  return { installed: optionalString(value, 'installed'), pinned: optionalString(value, 'pinned'), state }
}

/** `{ update }` when the parent sent one, nothing otherwise, so the key is not set to undefined. */
function updateField(data: Record<string, unknown>): { update?: HelperUpdateInfo } {
  const update = parseHelperUpdate(data.update ?? undefined)
  return update ? { update } : {}
}

/** The extras of a machine's page, or an UnreadableAnswer naming what was wrong. A value the parent left out is null. */
export function parseMachineExtras(data: unknown): MachineExtras {
  if (!isRecord(data)) throw new UnreadableAnswer('the machine is not an object')
  return {
    agent_version: optionalString(data, 'agent_version'),
    agent_build: optionalString(data, 'agent_build'),
    ...updateField(data),
    engine: parseEngine(data.engine),
    box: optionalString(data, 'box'),
    agent_port: optionalCount(data, 'agent_port'),
    ruvio: parseRuvio(data.ruvio),
  }
}
