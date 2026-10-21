// After Create VM is pressed the parent answers at once with an order; the VM exists when the machine has done it. This follows the order and finds the new VM, so the panel can open its page.
import type { Command, Machine } from './types.ts'

/** What the parent answers to a create: which order was queued and on which machine. */
export interface Created {
  commandId: string
  machine: string
}

export type NewVmOutcome =
  | { kind: 'ready'; machine: string; workload: string }
  | { kind: 'failed'; message: string }
  /** The order did not end within the wait. The VM may still appear; the person is told where to look. */
  | { kind: 'slow' }

/** The things this needs from outside, so the waiting can be tested without a network or a clock. */
export interface NewVmDeps {
  getCommand: (id: string) => Promise<Command>
  listMachines: () => Promise<Machine[]>
  pause: (ms: number) => Promise<void>
}

export const POLL_MS = 1000
export const MAX_POLLS = 60
const FAILED_WITHOUT_REASON = 'The machine could not make the VM.'

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)

/** The order and machine named in the parent's answer to a create, or null when the answer is not readable. */
export function parseCreated(answer: unknown): Created | null {
  const order = isRecord(answer) ? answer.command : null
  if (!isRecord(order) || typeof order.id !== 'string' || typeof order.machine !== 'string') return null
  return { commandId: order.id, machine: order.machine }
}

async function findWorkload(created: Created, name: string, deps: NewVmDeps): Promise<string | null> {
  const machines = await deps.listMachines()
  return machines.find((machine) => machine.id === created.machine)?.workloads.find((workload) => workload.name === name)?.id ?? null
}

/** One look: the outcome when the order has ended and the VM is listed, or null to look again later. */
async function look(created: Created, name: string, deps: NewVmDeps): Promise<NewVmOutcome | null> {
  const order = await deps.getCommand(created.commandId)
  if (order.state === 'failed') return { kind: 'failed', message: order.result?.error ?? FAILED_WITHOUT_REASON }
  if (order.state !== 'succeeded') return null
  const workload = await findWorkload(created, name, deps)
  return workload === null ? null : { kind: 'ready', machine: created.machine, workload }
}

/** Follows a create order until the VM is listed on its machine, the order fails, or the wait is over. */
export async function awaitNewVm(created: Created, name: string, deps: NewVmDeps): Promise<NewVmOutcome> {
  for (let poll = 0; poll < MAX_POLLS; poll++) {
    const outcome = await look(created, name, deps)
    if (outcome) return outcome
    await deps.pause(POLL_MS)
  }
  return { kind: 'slow' }
}
