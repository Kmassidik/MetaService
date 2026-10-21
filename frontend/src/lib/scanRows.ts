// What the Find machines table shows for a device that has been added. The scan itself is old by then, so the live machine list decides.
import type { Device, Machine } from './types.ts'

/** The name of the machine added at this device's address, or null when nobody has added it yet. */
export function addedName(row: Pick<Device, 'ip' | 'machine'>, machines: Machine[]): string | null {
  return row.machine ?? machines.find((machine) => machine.ip === row.ip)?.name ?? null
}
