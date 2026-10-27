// The VMs being made, kept while the person moves between pages (it lives in this module, not in a page), and gone with a reload: after a reload the parent's list of orders is the source.
// The rules of what is pending are in pendingVms.ts; this only remembers the orders this session made and the failed ones the person dismissed.
import { parseCommand } from './pendingVms.ts'
import type { Command } from './types.ts'

const REMEMBERED_ORDERS = 20

let made = $state<Command[]>([])
let dismissed = $state<string[]>([])
let watched = $state<string | null>(null)

/** The orders made or followed in this session. */
export const sessionOrders = (): Command[] => made

export const dismissedOrders = (): ReadonlySet<string> => new Set(dismissed)

/** Remembers an order, or its newer state. */
export function trackOrder(order: Command): void {
  made = [order, ...made.filter((entry) => entry.id !== order.id)].slice(0, REMEMBERED_ORDERS)
}

/** Once a successful list answer omits a delete, its accepted local copy must not keep the VM busy forever. */
export function reconcileDeleteOrders(listed: Command[]): void {
  const current = new Set(listed.map((order) => order.id))
  made = made.filter((order) => order.type !== 'delete' || current.has(order.id))
}

/** The order whose progress window is open, or null when none is. */
export const watchedOrder = (): string | null => watched

/** Closes the progress window. The order itself goes on in the background. */
export function stopWatching(): void {
  watched = null
}

/** Remembers the order inside the parent's answer to a create, and opens its progress window. False when the answer could not be read. */
export function trackCreateAnswer(answer: unknown): boolean {
  const order = parseCommand(answer)
  if (!order) return false
  trackOrder(order)
  watched = order.id
  return true
}

/** Hides a failed order for good (until a reload). */
export function dismissOrder(id: string): void {
  dismissed = [...dismissed, id]
}
