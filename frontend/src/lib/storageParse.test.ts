import { test, expect } from 'bun:test'
import { parseStorageReply } from './storageParse.ts'

const node = (parent: number, more: Record<string, unknown> = {}) => ({ parent, name: 'x', type: 'dir', bytes: 10, files: 1, items: 1, kind: 'code', reclaim: null, modified: 1793000000, ...more })
const map = (nodes: unknown[]) => ({ root: '/', finished_at: '2026-10-25T12:00:00Z', seconds: 1.5, entries: 9, unreadable: 0, disk: { total_bytes: 100, used_bytes: 40, free_bytes: 60 }, nodes })
const reply = (storage: unknown, state = 'online') => ({ state, storage })

test('a good answer is read as it is', () => {
  const parsed = parseStorageReply(reply({ scanning: false, progress: null, error: null, map: map([node(-1), node(0, { type: 'file', reclaim: 'build_output' })]) }))
  expect(parsed.state).toBe('online')
  expect(parsed.storage?.map?.nodes[1]).toEqual({ parent: 0, name: 'x', type: 'file', bytes: 10, files: 1, items: 1, kind: 'code', reclaim: 'build_output', modified: 1793000000 })
})

test('an older helper and an offline machine carry no storage', () => {
  expect(parseStorageReply(reply(null, 'old_helper'))).toEqual({ state: 'old_helper', storage: null })
  expect(parseStorageReply(reply(null, 'offline')).storage).toBeNull()
  expect(() => parseStorageReply(reply(null, 'sleeping'))).toThrow()
})

test('a scan in progress keeps its numbers and the last map may be missing', () => {
  const parsed = parseStorageReply(reply({ scanning: true, progress: { entries: 5, bytes: 50 }, error: null, map: null }))
  expect(parsed.storage).toEqual({ scanning: true, progress: { entries: 5, bytes: 50 }, error: null, map: null })
})

test('kinds and reasons from a newer helper read as other and none', () => {
  const parsed = parseStorageReply(reply({ scanning: false, progress: null, error: null, map: map([node(-1, { kind: 'holograms', reclaim: 'vaporised' })]) }))
  expect(parsed.storage?.map?.nodes[0]?.kind).toBe('other')
  expect(parsed.storage?.map?.nodes[0]?.reclaim).toBeNull()
})

test('an entry that does not sit in an earlier folder makes the answer unreadable', () => {
  const bad = [
    [node(0)],
    [node(-1), node(1)],
    [node(-1), node(0, { type: 'file' }), node(1)],
    [node(-1), node(-1)],
    [node(-1, { type: 'file' })],
    [node(-1), node(0, { type: 'folder' })],
    [],
  ]
  for (const nodes of bad) expect(() => parseStorageReply(reply({ scanning: false, progress: null, error: null, map: map(nodes) }))).toThrow()
})
