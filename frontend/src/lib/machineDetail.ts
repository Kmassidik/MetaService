// The parts of GET /api/machines/{id} that the machine list does not carry, checked before the page trusts them.
import type { Engine, Ruvio, RuvioState } from './types.ts'

export interface MachineExtras {
  agent_version: string | null
  engine: Engine | null
  box: string | null
  agent_port: number | null
  ruvio: Ruvio | null
}

const RUVIO_STATES: readonly RuvioState[] = ['unavailable', 'off', 'on', 'outdated', 'installing', 'removing']

export class UnreadableAnswer extends Error {}

type Record_ = Record<string, unknown>

const isRecord = (value: unknown): value is Record_ => typeof value === 'object' && value !== null && !Array.isArray(value)

function optionalString(source: Record_, key: string): string | null {
  const value = source[key]
  if (value === null || value === undefined) return null
  if (typeof value === 'string') return value
  throw new UnreadableAnswer(`${key} is not text`)
}

function optionalCount(source: Record_, key: string): number | null {
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

/** The extras of a machine's page, or an UnreadableAnswer naming what was wrong. A value the parent left out is null. */
export function parseMachineExtras(data: unknown): MachineExtras {
  if (!isRecord(data)) throw new UnreadableAnswer('the machine is not an object')
  return {
    agent_version: optionalString(data, 'agent_version'),
    engine: parseEngine(data.engine),
    box: optionalString(data, 'box'),
    agent_port: optionalCount(data, 'agent_port'),
    ruvio: parseRuvio(data.ruvio),
  }
}
