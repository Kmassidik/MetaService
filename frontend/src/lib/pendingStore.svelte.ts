// The VMs being made, kept while the person moves between pages (it lives in this module, not in a page), and gone with a reload: after a reload the parent's list of orders is the source.
// The rules of what is pending are in pendingVms.ts; this only remembers the orders this session made and the failed ones the person dismissed.
import { parseCommand } from './pendingVms.ts'
import type { Command } from './types.ts'

const REMEMBERED_ORDERS = 20

let made = $state<Command[]>([])
let dismissed = $state<string[]>([])

/** The orders made or followed in this session. */
export const sessionOrders = (): Command[] => made

export const dismissedOrders = (): ReadonlySet<string> => new Set(dismissed)

/** Remembers an order, or its newer state. */
export function trackOrder(order: Command): void {
  made = [order, ...made.filter((entry) => entry.id !== order.id)].slice(0, REMEMBERED_ORDERS)
}

/** Remembers the order inside the parent's answer to a create. False when the answer could not be read. */
export function trackCreateAnswer(answer: unknown): boolean {
  const order = parseCommand(answer)
  if (!order) return false
  trackOrder(order)
  return true
}

/** Hides a failed order for good (until a reload). */
export function dismissOrder(id: string): void {
  dismissed = [...dismissed, id]
}
