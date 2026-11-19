// The Machines map: lays out machines around the parent hub and gives each one its icon, state color
// and one-line subtitle. Pure layout math + data shaping, no DOM, so it is fully testable without a browser.
import type { Machine } from './types.ts'

export type MapIcon = 'hub' | 'fedora' | 'dgx' | 'rtx5090' | 'macmini' | 'macmini2' | 'macstudio' | 'macstudio2' | 'cloud'

export interface MapNode {
  id: string
  icon: MapIcon
  x: number
  y: number
  label: string
  subtitle: string
  state: 'online' | 'setup' | 'offline'
  machineId: string
}

export interface MapEdge {
  from: { x: number; y: number }
  to: { x: number; y: number }
  kind: 'mesh' | 'ssh' | 'public'
}

const HUB_X = 480
const HUB_Y = 285

/** The icon a machine gets, by its id (its role in the fleet). Unknown machines get the cloud icon. */
export function iconFor(machine: Machine): MapIcon {
  const byId: Record<string, MapIcon> = {
    'fedora': 'fedora',
    'dgx-spark': 'dgx',
    'rtx5090': 'rtx5090',
    'mac-studio': 'macstudio',
    'mac-mini': 'macmini',
    'mac-mini-2': 'macmini2',
    'mac-studio-2': 'macstudio2',
  }
  return byId[machine.id] ?? 'cloud'
}

/** One-line subtitle: the connection path. Share a PC (10.77.x) reads as the mesh address. */
export function subtitleFor(machine: Machine): string {
  if (machine.ip?.startsWith('10.77.')) return `mesh · ${machine.ip}`
  if (machine.ip) return machine.ip
  return machine.state === 'offline' ? 'offline' : 'no address'
}

/** The state a node shows: offline first, then needs setup (problems), else online. */
export function stateFor(machine: Machine): MapNode['state'] {
  if (machine.state === 'offline') return 'offline'
  if ((machine.problems?.length ?? 0) > 0) return 'setup'
  return 'online'
}

/** A link from the hub to this machine: mesh for 10.77.x, public for public IPs, ssh for the office LAN. */
export function edgeKindFor(machine: Machine): MapEdge['kind'] {
  if (machine.ip?.startsWith('10.77.')) return 'mesh'
  if (machine.ip?.startsWith('202.')) return 'public'
  return 'ssh'
}

/** Six preset slots around the hub (matching the mock's layout), by fleet size: 1..N on a ring otherwise. */
const PRESETS: Array<[number, number]> = [
  [210, 140], [750, 140], [180, 430], [780, 430], [300, 510], [660, 510],
]

export function layout(machines: Machine[], hubName: string): { nodes: MapNode[]; edges: MapEdge[] } {
  const others = machines.filter((m) => m.id !== hubName)
  const nodes: MapNode[] = []
  const edges: MapEdge[] = []
  nodes.push({
    id: '__hub__',
    icon: 'hub',
    x: HUB_X,
    y: HUB_Y,
    label: hubName,
    subtitle: 'hub · parent',
    state: 'online',
    machineId: hubName,
  })
  others.forEach((machine, i) => {
    let x: number, y: number
    if (others.length <= PRESETS.length) {
      const preset = PRESETS[i]!
      x = preset[0]
      y = preset[1]
    } else {
      const angle = (i / others.length) * 2 * Math.PI - Math.PI / 2
      const rx = 300, ry = 210
      x = Math.round(HUB_X + rx * Math.cos(angle))
      y = Math.round(HUB_Y + ry * Math.sin(angle))
    }
    nodes.push({
      id: machine.id,
      icon: iconFor(machine),
      x,
      y,
      label: machine.name,
      subtitle: subtitleFor(machine),
      state: stateFor(machine),
      machineId: machine.id,
    })
    edges.push({ from: { x: HUB_X, y: HUB_Y }, to: { x, y }, kind: edgeKindFor(machine) })
  })
  return { nodes, edges }
}

/** Which of the two routes a node click goes to: the machine's detail page (same href as a card). */
export function machineHrefFor(node: MapNode): string {
  return `#/machines/details?id=${encodeURIComponent(node.machineId)}`
}
