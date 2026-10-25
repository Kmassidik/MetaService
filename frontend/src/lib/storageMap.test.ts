import { test, expect } from 'bun:test'
import { childrenOf, crumbsOf, HEADER_PX, HIDDEN, hiddenBytes, layoutTiles, MAX_TILES, nodeLabel, pathOf, squarify, worthALook, type Rect } from './storageMap.ts'
import type { StorageMap, StorageNode } from './types.ts'

const GIB = 1024 ** 3

function entry(parent: number, name: string, bytes: number, more: Partial<StorageNode> = {}): StorageNode {
  return { parent, name, type: 'dir', bytes, files: 1, items: 1, kind: 'other', reclaim: null, modified: null, ...more }
}

/** / holds home (ops: .cache, projects) and var; 5 GiB of the used space is hidden from the scan. */
function sample(): StorageMap {
  const nodes = [
    entry(-1, '/', 100 * GIB),
    entry(0, 'home', 70 * GIB, { kind: 'code' }),
    entry(1, 'ops', 70 * GIB, { kind: 'code' }),
    entry(2, '.cache', 40 * GIB, { kind: 'cache', reclaim: 'regenerable' }),
    entry(3, 'huggingface', 39 * GIB, { kind: 'cache', reclaim: 'regenerable' }),
    entry(2, 'projects', 30 * GIB, { kind: 'code' }),
    entry(5, 'target', 3 * GIB, { kind: 'code', reclaim: 'build_output' }),
    entry(5, '', 1 * GIB, { type: 'rest', items: 771 }),
    entry(0, 'var', 30 * GIB),
    entry(8, 'swap.img', 16 * GIB, { type: 'file', items: 0 }),
  ]
  return { root: '/', finished_at: '2026-10-25T12:00:00Z', seconds: 4.2, entries: 1000, unreadable: 2, disk: { total_bytes: 400 * GIB, used_bytes: 105 * GIB, free_bytes: 295 * GIB }, nodes }
}

const area = (rect: Rect) => rect.w * rect.h

test('squarify fills the rectangle with areas in proportion to the sizes', () => {
  const rect = { x: 10, y: 20, w: 600, h: 400 }
  const sizes = [6, 6, 4, 3, 2, 2, 1]
  const parts = squarify(sizes, rect)
  const sum = sizes.reduce((a, b) => a + b, 0)
  parts.forEach((part, index) => {
    expect(area(part)).toBeCloseTo((sizes[index]! / sum) * area(rect), 6)
    expect(part.x).toBeGreaterThanOrEqual(rect.x - 1e-9)
    expect(part.y).toBeGreaterThanOrEqual(rect.y - 1e-9)
    expect(part.x + part.w).toBeLessThanOrEqual(rect.x + rect.w + 1e-9)
    expect(part.y + part.h).toBeLessThanOrEqual(rect.y + rect.h + 1e-9)
  })
  // Squarified: no tile is a sliver.
  for (const part of parts) expect(Math.max(part.w / part.h, part.h / part.w)).toBeLessThan(4)
})

test('squarify gives nothing to empty sizes and copes with an empty rectangle', () => {
  expect(squarify([5, 0], { x: 0, y: 0, w: 10, h: 10 })[1]).toEqual({ x: 0, y: 0, w: 0, h: 0 })
  expect(squarify([], { x: 0, y: 0, w: 10, h: 10 })).toEqual([])
  expect(squarify([1, 2], { x: 0, y: 0, w: 0, h: 10 }).every((part) => part.w === 0)).toBe(true)
})

test('children, crumbs and paths follow the parent places', () => {
  const map = sample()
  const children = childrenOf(map.nodes)
  expect(children[0]).toEqual([1, 8])
  expect(children[5]).toEqual([6, 7])
  expect(crumbsOf(map.nodes, 4)).toEqual([0, 1, 2, 3, 4])
  expect(pathOf(map, 4)).toBe('/home/ops/.cache/huggingface')
  expect(pathOf(map, 0)).toBe('/')
  expect(pathOf(map, 7)).toBe('/home/ops/projects')
  expect(nodeLabel(map.nodes[7]!)).toBe('+771 more')
})

test('the hidden space is the used space the scan did not see, never below zero', () => {
  const map = sample()
  expect(hiddenBytes(map)).toBe(5 * GIB)
  expect(hiddenBytes({ ...map, disk: { ...map.disk, used_bytes: 1 } })).toBe(0)
})

test('the top level carries one hidden tile, in size order, and only at the scanned folder', () => {
  const map = sample()
  const children = childrenOf(map.nodes)
  const rect = { x: 0, y: 0, w: 800, h: 500 }
  const top = layoutTiles(map, children, 0, rect, 1)
  expect(top.map((tile) => tile.node)).toEqual([1, 8, HIDDEN])
  const shares = top.map((tile) => area(tile) / area(rect))
  expect(shares[0]).toBeCloseTo(70 / 105, 6)
  expect(shares[2]).toBeCloseTo(5 / 105, 6)
  expect(layoutTiles(map, children, 1, rect, 1).some((tile) => tile.node === HIDDEN)).toBe(false)
})

test('folders open up to the chosen depth, with a name strip, and come before what they hold', () => {
  const map = sample()
  const children = childrenOf(map.nodes)
  const tiles = layoutTiles(map, children, 0, { x: 0, y: 0, w: 900, h: 600 }, 3)
  const placeOf = (node: number) => tiles.findIndex((tile) => tile.node === node)
  expect(placeOf(2)).toBeGreaterThan(placeOf(1))
  expect(placeOf(3)).toBeGreaterThan(placeOf(2))
  expect(placeOf(4)).toBe(-1) // depth 4: not drawn at depth 3
  expect(tiles[placeOf(1)]!.header).toBe(HEADER_PX)
  expect(tiles[placeOf(3)]!.header).toBe(0) // the deepest drawn level is a plain tile
  const home = tiles[placeOf(1)]!
  const ops = tiles[placeOf(2)]!
  expect(ops.y).toBeGreaterThanOrEqual(home.y + HEADER_PX)
  expect(ops.x + ops.w).toBeLessThanOrEqual(home.x + home.w)
})

test('a huge map is cut at the tile limit, biggest levels first', () => {
  const nodes: StorageNode[] = [entry(-1, '/', 5000)]
  for (let index = 0; index < 50; index += 1) nodes.push(entry(0, `d${index}`, 100))
  for (let index = 0; index < 4000; index += 1) nodes.push(entry(1 + (index % 50), `f${index}`, 1, { type: 'file', items: 0 }))
  const map: StorageMap = { ...sample(), nodes, disk: { total_bytes: 10000, used_bytes: 5000, free_bytes: 5000 } }
  const tiles = layoutTiles(map, childrenOf(nodes), 0, { x: 0, y: 0, w: 4000, h: 4000 }, 6)
  expect(tiles.length).toBeLessThanOrEqual(MAX_TILES)
  expect(tiles.filter((tile) => tile.depth === 1)).toHaveLength(50)
})

test('worth a look lists the top of each reclaimable branch, largest first, never one inside another', () => {
  const map = sample()
  expect(worthALook(map)).toEqual([3, 6])
  expect(worthALook(map, 1)).toEqual([3])
})
