// The Storage tab's treemap, drawn the way disktree draws a disk: nested squarified tiles whose area is the space taken, coloured by kind,
// hatched when the space could be had back. Pure functions, no DOM.
import type { StorageKind, StorageMap, StorageNode, StorageReclaim } from './types.ts'

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

/** One drawn tile. `node` is a place in the map's list, or HIDDEN for the space the scan could not see. */
export interface Tile extends Rect {
  node: number
  depth: number
  /** Height of the name strip at the top of a folder whose contents are drawn inside it; 0 for a plain tile. */
  header: number
}

export const HIDDEN = -1
export const HEADER_PX = 17
const PAD_PX = 2
/** A folder opens up only when its tile is at least this big on both sides. */
const OPEN_MIN_PX = 44
/** Thinner than this a tile cannot be seen, so it is not drawn. */
const MIN_SIDE_PX = 2
/** The most tiles drawn at once; the biggest levels come first. */
export const MAX_TILES = 1500
export const MIN_DEPTH = 1
export const MAX_DEPTH = 6
export const DEFAULT_DEPTH = 3
/** "Worth a look" leaves out anything smaller than this, as disktree does. */
const WORTH_MIN_BYTES = 64 * 1024 * 1024

export const KIND_LABELS: Record<StorageKind, string> = {
  code: 'Code', agent: 'Agent scratch', toolchain: 'Toolchains', synced: 'Synced', git: 'Git', media: 'Media', documents: 'Documents', cache: 'Cache',
  vms: 'VMs & containers', other: 'Other',
}
/** The legend's order: disktree's, then ours. */
export const LEGEND_KINDS: readonly StorageKind[] = ['code', 'agent', 'toolchain', 'synced', 'git', 'media', 'documents', 'cache', 'vms']

export const RECLAIM_LABELS: Record<StorageReclaim, string> = {
  regenerable: 'regenerable', sync_history: 'sync history', package_store: 'package store', build_output: 'build output', reinstallable: 'reinstallable',
  sandbox_layers: 'sandbox layers', snapshots: 'snapshots', trash: 'trash', temporary: 'temporary',
}

/** Each entry's children, in list order (largest first, as the helper sends them). */
export function childrenOf(nodes: readonly StorageNode[]): number[][] {
  const children: number[][] = nodes.map(() => [])
  nodes.forEach((node, place) => {
    if (place > 0) children[node.parent]?.push(place)
  })
  return children
}

/** The space the filesystem says is used but the scan could not see (folders only root or another user may open). */
export const hiddenBytes = (map: StorageMap): number => Math.max(0, map.disk.used_bytes - (map.nodes[0]?.bytes ?? 0))

/** What a tile is called: a rest says how many entries it stands for, like disktree's "+771 more". */
export function nodeLabel(node: StorageNode): string {
  if (node.type === 'rest') return `+${node.items.toLocaleString('en-US')} more`
  return node.name || '(no name)'
}

/** The places from the scanned folder down to `place`, both included. */
export function crumbsOf(nodes: readonly StorageNode[], place: number): number[] {
  const crumbs: number[] = []
  for (let at = place; at >= 0; at = nodes[at]?.parent ?? -1) crumbs.unshift(at)
  return crumbs
}

/** The full path of an entry, starting at the scanned folder. A rest gives its folder's path. */
export function pathOf(map: StorageMap, place: number): string {
  const names = crumbsOf(map.nodes, place).slice(1).flatMap((at) => (map.nodes[at]?.type === 'rest' ? [] : [map.nodes[at]?.name ?? '']))
  const root = map.root.endsWith('/') ? map.root.slice(0, -1) : map.root
  return names.length ? `${root}/${names.join('/')}` : map.root
}

const total = (values: readonly number[], from: number, to: number): number => {
  let sum = 0
  for (let at = from; at < to; at += 1) sum += values[at] ?? 0
  return sum
}

/** How far from square the worst tile of a row would be. */
function worst(areas: readonly number[], from: number, to: number, side: number): number {
  const sum = total(areas, from, to)
  let largest = 0
  let smallest = Infinity
  for (let at = from; at < to; at += 1) {
    largest = Math.max(largest, areas[at] ?? 0)
    smallest = Math.min(smallest, areas[at] ?? 0)
  }
  const sideSquared = side * side
  return Math.max((sideSquared * largest) / (sum * sum), (sum * sum) / (sideSquared * smallest))
}

/** Squarified treemap (Bruls, Huizing and van Wijk): one rectangle per size, areas in proportion, as square as it can. `sizes` largest first; a size of 0 or less gets an empty rectangle. */
export function squarify(sizes: readonly number[], rect: Rect): Rect[] {
  const out: Rect[] = sizes.map(() => ({ x: rect.x, y: rect.y, w: 0, h: 0 }))
  const count = sizes.findIndex((size) => !(size > 0))
  const used = count === -1 ? sizes.length : count
  const sum = total(sizes, 0, used)
  if (used === 0 || sum <= 0 || rect.w <= 0 || rect.h <= 0) return out
  const scale = (rect.w * rect.h) / sum
  const areas = sizes.slice(0, used).map((size) => size * scale)
  let { x, y, w, h } = rect
  let start = 0
  while (start < used) {
    const side = Math.min(w, h)
    let end = start + 1
    while (end < used && worst(areas, start, end + 1, side) <= worst(areas, start, end, side)) end += 1
    const rowArea = total(areas, start, end)
    if (w >= h) {
      const width = h > 0 ? rowArea / h : 0
      let at = y
      for (let place = start; place < end; place += 1) {
        const height = width > 0 ? (areas[place] ?? 0) / width : 0
        out[place] = { x, y: at, w: width, h: height }
        at += height
      }
      x += width
      w -= width
    } else {
      const height = w > 0 ? rowArea / w : 0
      let at = x
      for (let place = start; place < end; place += 1) {
        const width = height > 0 ? (areas[place] ?? 0) / height : 0
        out[place] = { x: at, y, w: width, h: height }
        at += width
      }
      y += height
      h -= height
    }
    start = end
  }
  return out
}

interface Pending {
  node: number
  rect: Rect
  depth: number
}

/** The children of `place` laid out in `rect`; for the scanned folder, the hidden space is one more tile among them, in size order. */
function laidOut(map: StorageMap, children: readonly number[][], place: number, rect: Rect, depth: number, hidden: number): Pending[] {
  const order = [...(children[place] ?? [])]
  if (hidden > 0) {
    const at = order.findIndex((child) => (map.nodes[child]?.bytes ?? 0) < hidden)
    order.splice(at === -1 ? order.length : at, 0, HIDDEN)
  }
  const sizes = order.map((child) => (child === HIDDEN ? hidden : (map.nodes[child]?.bytes ?? 0)))
  return squarify(sizes, rect).map((part, index) => ({ node: order[index] ?? HIDDEN, rect: part, depth }))
}

/** The tiles for `focus` drawn in `rect`, `depth` levels deep. Level by level, so when there are too many the deepest are left out. Folders come before what they hold. */
export function layoutTiles(map: StorageMap, children: readonly number[][], focus: number, rect: Rect, depth: number): Tile[] {
  const levels = Math.min(Math.max(Math.round(depth), MIN_DEPTH), MAX_DEPTH)
  const hidden = focus === 0 ? hiddenBytes(map) : 0
  const queue: Pending[] = laidOut(map, children, focus, rect, 1, hidden)
  const tiles: Tile[] = []
  for (let next = 0; next < queue.length && tiles.length < MAX_TILES; next += 1) {
    const { node, rect: area, depth: level } = queue[next] as Pending
    if (area.w < MIN_SIDE_PX || area.h < MIN_SIDE_PX) continue
    const entry = node === HIDDEN ? undefined : map.nodes[node]
    const opens = entry?.type === 'dir' && level < levels && (children[node]?.length ?? 0) > 0 && area.w >= OPEN_MIN_PX && area.h >= OPEN_MIN_PX
    tiles.push({ node, ...area, depth: level, header: opens ? HEADER_PX : 0 })
    if (opens) {
      const inner = { x: area.x + PAD_PX, y: area.y + HEADER_PX, w: area.w - 2 * PAD_PX, h: area.h - HEADER_PX - PAD_PX }
      queue.push(...laidOut(map, children, node, inner, level + 1, 0))
    }
  }
  return tiles
}

/** disktree's "Worth a look": the largest entries whose space could be had back, never one inside another, largest first. */
export function worthALook(map: StorageMap, limit = 5): number[] {
  const found = map.nodes.flatMap((node, place) => {
    const parent = map.nodes[node.parent]
    return node.reclaim !== null && (place === 0 || parent?.reclaim === null) && node.bytes >= WORTH_MIN_BYTES ? [place] : []
  })
  return found.sort((a, b) => (map.nodes[b]?.bytes ?? 0) - (map.nodes[a]?.bytes ?? 0)).slice(0, limit)
}

/** The largest folders right inside `place`, for the list beside the map (keyboard users reach every folder from here). */
export function largestFolders(map: StorageMap, children: readonly number[][], place: number, limit = 8): number[] {
  return (children[place] ?? []).filter((child) => map.nodes[child]?.type === 'dir').slice(0, limit)
}
