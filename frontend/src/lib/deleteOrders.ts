// Delete orders keep a VM busy after the POST has answered. The accepted order gives immediate feedback;
// the machine's own `deleting` state keeps it truthful after a reload or when the order leaves the recent list.
import { cleanFailureText } from './stoppedReason.ts'
import type { Command, Machine } from './types.ts'

const ACTIVE_STATES: Record<string, true> = { queued: true, running: true }
const DELETING_STATE = 'deleting'
const DELETE_FAILED_TEXT = 'The VM could not be deleted.'

const isActiveDelete = (order: Command): order is Command & { workload_id: string } => order.type === 'delete' && ACTIVE_STATES[order.state] === true && typeof order.workload_id === 'string'
const key = (machine: string, workload: string): string => `${machine}\0${workload}`

/** True while any accepted delete is queued/running, or a machine still reports its VM as deleting. */
export function hasDeleteInProgress(machines: Machine[], orders: Command[]): boolean {
  return orders.some(isActiveDelete) || machines.some((machine) => machine.workloads.some((workload) => workload.state === DELETING_STATE))
}

/** Overlays accepted deletes on the latest machine list, so every VM view agrees before the next heartbeat. */
export function withDeleting(machines: Machine[], orders: Command[]): Machine[] {
  const active = new Set(orders.filter(isActiveDelete).map((order) => key(order.machine, order.workload_id)))
  if (active.size === 0) return machines
  let anyChanged = false
  const shown = machines.map((machine) => {
    const workloads = machine.workloads.map((workload) => active.has(key(machine.id, workload.id)) && workload.state !== DELETING_STATE ? { ...workload, state: DELETING_STATE } : workload)
    const changed = workloads.some((workload, index) => workload !== machine.workloads[index])
    if (changed) anyChanged = true
    return changed ? { ...machine, workloads } : machine
  })
  return anyChanged ? shown : machines
}

function newestDelete(orders: Command[], machine: string, workload: string): Command | null {
  const matches = orders.filter((order) => order.type === 'delete' && order.machine === machine && order.workload_id === workload)
  return matches.reduce<Command | null>((newest, order) => !newest || Date.parse(order.created_at) > Date.parse(newest.created_at) ? order : newest, null)
}

/** The newest failed delete's real helper reason. A newer attempt or success clears the old failure. */
export function deleteFailure(orders: Command[], machine: string, workload: string): string | null {
  const order = newestDelete(orders, machine, workload)
  if (order?.state !== 'failed') return null
  return cleanFailureText(order.result?.error ?? '').trim() || DELETE_FAILED_TEXT
}
