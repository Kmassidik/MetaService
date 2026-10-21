// VMs that are being made. The parent answers a create at once with an order, but the machine only lists the VM on a later heartbeat, so for a while the VM is in no list.
// These pure functions turn the orders (and the machines' lists) into the "Creating…" rows the pages show. No DOM, no network, no clock of their own.
import type { Command, CommandResult, Machine, Workload } from './types.ts'

export type PendingStage = 'waiting' | 'creating' | 'starting' | 'failed'
export type StepState = 'done' | 'now' | 'next'

export interface PendingVm {
  /** The order's id: also the key of the row. */
  id: string
  machine: string
  machineName: string
  name: string
  stage: PendingStage
  /** Why it failed, in a sentence. Null unless the stage is `failed`. */
  reason: string | null
  /** Said when the order is taking very long. Null otherwise. */
  note: string | null
}

const SECOND_MS = 1000
const MINUTE_MS = 60 * SECOND_MS
/** After this long without an end, waiting or creating is called slow. */
export const SLOW_AFTER_MS = 3 * MINUTE_MS
/** A made VM is normally listed within one heartbeat (5 to 15 seconds); after this long the row says so. */
export const UNREPORTED_AFTER_MS = MINUTE_MS
/** A made VM that no list shows for this long is no longer pending (it may have been deleted since). */
export const MADE_SHOWN_MS = 5 * MINUTE_MS
/** A failed order stays this long, so a reload still shows what went wrong. */
export const FAILED_SHOWN_MS = 30 * MINUTE_MS

const CREATING_STATES = new Set(['provisioning', 'creating', 'starting'])
const UNNAMED = 'new VM'
const WITHOUT_REASON = 'The machine could not make the VM.'

const STAGE_TEXT: Record<PendingStage, string> = { waiting: 'Waiting for the machine', creating: 'Creating', starting: 'Starting', failed: 'Could not make the VM' }
const STEP_ORDER: PendingStage[] = ['waiting', 'creating', 'starting']
const SLOW_NOTES: Record<Exclude<PendingStage, 'failed'>, string> = {
  waiting: 'Still waiting for the machine. It may be busy or offline.',
  creating: 'This is taking longer than usual. The machine is still working on it.',
  starting: 'The machine has made it but has not reported it yet. It will show here by itself.',
}
const ORDER_STAGES: Record<string, PendingStage> = { queued: 'waiting', running: 'creating', succeeded: 'starting', failed: 'failed' }

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)

/** The order inside the parent's answer to a create (`{ command: {...} }`), or null when the answer is not readable. */
export function parseCommand(answer: unknown): Command | null {
  const order = isRecord(answer) ? answer.command : null
  if (!isRecord(order)) return null
  const { id, machine, type, state, created_at: createdAt, params } = order
  if (typeof id !== 'string' || typeof machine !== 'string' || typeof type !== 'string' || typeof state !== 'string') return null
  return { id, machine, type, state, created_at: typeof createdAt === 'string' ? createdAt : '', params: isRecord(params) ? params : {}, result: parseResult(order.result), finished_at: typeof order.finished_at === 'string' ? order.finished_at : null }
}

function parseResult(value: unknown): CommandResult | null {
  if (!isRecord(value)) return null
  const result: CommandResult = {}
  if (typeof value.error === 'string') result.error = value.error
  if (typeof value.workload_id === 'string') result.workload_id = value.workload_id
  return result
}

/** The orders from the parent's list and the ones this session made. The same order counts once, and the list's copy wins because it is newer. */
export function mergeOrders(listed: Command[], local: Command[]): Command[] {
  const known = new Set(listed.map((order) => order.id))
  return [...listed, ...local.filter((order) => !known.has(order.id))]
}

/** A reason as a sentence: first letter big, ending with a full stop. */
export function reasonText(result: CommandResult | null | undefined): string {
  const text = result?.error?.trim()
  if (!text) return WITHOUT_REASON
  const sentence = text[0]?.toUpperCase() + text.slice(1)
  return /[.!?]$/.test(sentence) ? sentence : `${sentence}.`
}

export const stageText = (stage: PendingStage): string => STAGE_TEXT[stage]

/** The three steps (waiting for the machine, creating, starting) and where the VM is among them. A failed VM is at none of them. */
export function stageSteps(stage: PendingStage): StepState[] {
  const at = STEP_ORDER.indexOf(stage)
  return STEP_ORDER.map((_, index) => stepState(index, at))
}

function stepState(index: number, at: number): StepState {
  if (at < 0 || index > at) return 'next'
  return index === at ? 'now' : 'done'
}

const orderName = (order: Command): string => (typeof order.params.name === 'string' && order.params.name !== '' ? order.params.name : UNNAMED)

function ageMs(since: string | null | undefined, now: number): number {
  const time = since ? Date.parse(since) : Number.NaN
  return Number.isNaN(time) ? 0 : now - time
}

/** True when the machine already lists this order's VM. By id when the order knows it; before that, a VM of the same name that is itself being made. */
function isListed(order: Command, on: Machine | undefined): boolean {
  if (!on) return false
  const id = order.result?.workload_id
  if (id) return on.workloads.some((workload: Workload) => workload.id === id)
  return on.workloads.some((workload: Workload) => workload.name === orderName(order) && CREATING_STATES.has(workload.state))
}

function isStale(order: Command, stage: PendingStage, now: number): boolean {
  if (stage === 'failed') return ageMs(order.finished_at ?? order.created_at, now) > FAILED_SHOWN_MS
  return stage === 'starting' && ageMs(order.finished_at ?? order.created_at, now) > MADE_SHOWN_MS
}

function noteFor(order: Command, stage: PendingStage, now: number): string | null {
  if (stage === 'failed') return null
  if (stage === 'starting') return ageMs(order.finished_at ?? order.created_at, now) > UNREPORTED_AFTER_MS ? SLOW_NOTES.starting : null
  return ageMs(order.created_at, now) > SLOW_AFTER_MS ? SLOW_NOTES[stage] : null
}

function entryFor(order: Command, machines: Machine[], now: number, dismissed: ReadonlySet<string>): PendingVm | null {
  const stage = ORDER_STAGES[order.state]
  if (order.type !== 'create' || !stage || dismissed.has(order.id) || isStale(order, stage, now)) return null
  const on = machines.find((machine) => machine.id === order.machine)
  if (stage !== 'failed' && (!on || isListed(order, on))) return null
  return { id: order.id, machine: order.machine, machineName: on?.name ?? order.machine, name: orderName(order), stage, reason: stage === 'failed' ? reasonText(order.result) : null, note: noteFor(order, stage, now) }
}

/** The VMs that are being made or could not be made, newest first: orders to create a VM that no machine lists yet, and failed ones the person has not dismissed. */
export function pendingVms(orders: Command[], machines: Machine[], now: number, dismissed: ReadonlySet<string>): PendingVm[] {
  const newestFirst = [...orders].sort((left, right) => ageMs(left.created_at, now) - ageMs(right.created_at, now))
  return newestFirst.map((order) => entryFor(order, machines, now, dismissed)).filter((entry): entry is PendingVm => entry !== null)
}

/** The pending VMs of one machine, or all of them when no machine is given. */
export const pendingFor = (pending: PendingVm[], machineId: string | null): PendingVm[] => (machineId === null ? pending : pending.filter((entry) => entry.machine === machineId))
