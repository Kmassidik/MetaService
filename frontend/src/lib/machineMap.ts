// The Machines map, canvas edition. Pure data shaping and layout math, no DOM — the drawing lives in
// MachineCanvas.svelte. Everything here is testable without a browser.
import type { Machine } from './types.ts'

export type MapIconKind = 'hub' | 'fedora' | 'dgx' | 'rtx5090' | 'macmini' | 'macmini2' | 'macstudio' | 'macstudio2' | 'cloud'

export interface CanvasNode {
  id: string
  machineId: string
  icon: MapIconKind
  /** Preset slot; the canvas may overwrite x/y after a drag. */
  x: number
  y: number
  label: string
  subtitle: string
  state: 'online' | 'setup' | 'offline'
  isHub: boolean
}

export interface CanvasEdge {
  fromId: string
  toId: string
  kind: 'mesh' | 'ssh' | 'public'
}

const HUB_X = 0
const HUB_Y = 0

/** Preset slots around the hub in world coordinates (relative to the hub at 0,0). */
const PRESETS: Array<[number, number]> = [
  [-210, -135],
  [220, -125],
  [-245, 45],
  [235, 115],
  [-140, 155],
  [75, 155],
]

const RING_RX = 300
const RING_RY = 210

/** The icon a machine gets, by its id (its role in the fleet). Unknown machines get the cloud icon. */
export function iconFor(machine: Machine): MapIconKind {
  const byId: Record<string, MapIconKind> = {
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
export function stateFor(machine: Machine): CanvasNode['state'] {
  if (machine.state === 'offline') return 'offline'
  if ((machine.problems?.length ?? 0) > 0) return 'setup'
  return 'online'
}

/** The edge kind from the hub to this machine: mesh for 10.77.x, public for public IPs, ssh for the office LAN. */
export function edgeKindFor(machine: Machine): CanvasEdge['kind'] {
  if (machine.ip?.startsWith('10.77.')) return 'mesh'
  if (machine.ip?.startsWith('202.')) return 'public'
  return 'ssh'
}

const HUB_ID = '__hub__'

export function hubNodeId(): string {
  return HUB_ID
}

/** Builds nodes (hub at 0,0, machines around it) and hub→machine edges. Drags are applied after, in the canvas. */
export function buildGraph(machines: Machine[], hubName: string): { nodes: CanvasNode[]; edges: CanvasEdge[] } {
  const nodes: CanvasNode[] = [
    { id: HUB_ID, machineId: hubName, icon: 'hub', x: HUB_X, y: HUB_Y, label: hubName, subtitle: 'hub · parent', state: 'online', isHub: true },
  ]
  const edges: CanvasEdge[] = []
  const others = machines.filter((m) => m.id !== hubName)
  others.forEach((machine, i) => {
    let x: number, y: number
    if (others.length <= PRESETS.length) {
      const preset = PRESETS[i]!
      x = preset[0]
      y = preset[1]
    } else {
      const angle = (i / others.length) * 2 * Math.PI - Math.PI / 2
      x = Math.round(HUB_X + RING_RX * Math.cos(angle))
      y = Math.round(HUB_Y + RING_RY * Math.sin(angle))
    }
    nodes.push({
      id: machine.id,
      machineId: machine.id,
      icon: iconFor(machine),
      x,
      y,
      label: machine.name,
      subtitle: subtitleFor(machine),
      state: stateFor(machine),
      isHub: false,
    })
    edges.push({ fromId: HUB_ID, toId: machine.id, kind: edgeKindFor(machine) })
  })
  return { nodes, edges }
}

/** Which route a node opens: the machine's detail page (same href as a card). */
export function machineHrefFor(machineId: string): string {
  return `#/machines/details?id=${encodeURIComponent(machineId)}`
}
