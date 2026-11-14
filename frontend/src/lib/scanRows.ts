// What the Find machines table shows for a device that has been added. The scan itself is old by then, so the live machine list decides.
import type { Device, Machine } from './types.ts'

export type RowStatus = { kind: 'router' } | { kind: 'added'; name: string } | { kind: 'agent' } | { kind: 'add' }

const IP_SEPARATOR = '.'
const DECIMAL_RADIX = 10
const KNOWN_ROW_PREFIX = 'known-'

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

/** Orders two dotted addresses by their numbers, so 192.168.0.9 comes before 192.168.0.10. */
export function compareIp(left: string, right: string): number {
  const leftParts = left.split(IP_SEPARATOR).map((part) => Number.parseInt(part, DECIMAL_RADIX) || 0)
  const rightParts = right.split(IP_SEPARATOR).map((part) => Number.parseInt(part, DECIMAL_RADIX) || 0)
  const length = Math.max(leftParts.length, rightParts.length)
  for (let index = 0; index < length; index++) {
    const difference = (leftParts[index] ?? 0) - (rightParts[index] ?? 0)
    if (difference !== 0) return difference
  }
  return 0
}

/** A registered machine as a table row, marked added, so it shows even when the scan did not see it. */
function knownMachineRow(machine: Machine & { ip: string }): Device {
  return { id: `${KNOWN_ROW_PREFIX}${machine.id}`, ip: machine.ip, hostname: machine.name, mac: null, vendor: null, agent_port_open: false, machine: machine.name }
}

/** The scan rows plus one row for each registered machine whose address the scan did not list (machines that share an address each get a row), sorted by address. */
export function withKnownMachines(rows: Device[], machines: Machine[]): Device[] {
  const scanned = new Set(rows.map((row) => row.ip))
  const extra: Device[] = []
  // Only the scan decides what is already listed: two machines can share one public address (different SSH ports), and each keeps its own row.
  for (const machine of machines) {
    if (!machine.ip || scanned.has(machine.ip)) continue
    extra.push(knownMachineRow({ ...machine, ip: machine.ip }))
  }
  return [...rows, ...extra].sort((left, right) => compareIp(left.ip, right.ip))
}
