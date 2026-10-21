// What the Find machines table shows for a device that has been added. The scan itself is old by then, so the live machine list decides.
import type { Device, Machine } from './types.ts'

export type RowStatus = { kind: 'router' } | { kind: 'added'; name: string } | { kind: 'agent' } | { kind: 'add' }

/** The name of the machine added at this device's address, or null when nobody has added it yet. */
export function addedName(row: Pick<Device, 'ip' | 'machine'>, machines: Machine[]): string | null {
  return row.machine ?? machines.find((machine) => machine.ip === row.ip)?.name ?? null
}

/** What a row of the table offers: the router is left alone, an added device shows its name, a device with an Agent says so, and anything else (this computer too) can be added. */
export function rowStatus(row: Pick<Device, 'ip' | 'machine' | 'agent_port_open'>, machines: Machine[], where: { gateway: boolean }): RowStatus {
  if (where.gateway) return { kind: 'router' }
  const name = addedName(row, machines)
  if (name !== null) return { kind: 'added', name }
  return row.agent_port_open ? { kind: 'agent' } : { kind: 'add' }
}
