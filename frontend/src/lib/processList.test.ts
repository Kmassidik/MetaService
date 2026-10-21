import { test, expect } from 'bun:test'
import { filterProcesses, processesFromReply } from './processList.ts'
import { sampleStats } from './stats.test.ts'
import type { MachineStatsReply, StatsProcess } from './types.ts'

const make = (count: number): StatsProcess[] => Array.from({ length: count }, (_, index) => ({ pid: index + 1, name: `prog${index + 1}`, user: index % 2 ? 'root' : 'kurnia', cpu_percent: 1, memory_bytes: 1 }))

const reply = (extra: Partial<MachineStatsReply> = {}): MachineStatsReply => ({ state: 'online', last_seen: null, fetched_at: null, stats: sampleStats({ processes: make(3) }), ...extra })

test('without a filter every program the machine reported is listed, in order', () => {
  expect(filterProcesses(make(15), '').map((p) => p.pid)).toEqual(make(15).map((p) => p.pid))
  expect(filterProcesses(make(15), '   ').length).toBe(15)
})

test('the filter matches name or user as plain text, ignoring case and spaces around it', () => {
  expect(filterProcesses(make(15), ' PROG1 ').map((p) => p.name)).toEqual(['prog1', 'prog10', 'prog11', 'prog12', 'prog13', 'prog14', 'prog15'])
  expect(filterProcesses(make(15), 'root').length).toBe(7)
})

test('the filter searches all 15, not just the first few', () => {
  expect(filterProcesses(make(15), 'prog15').map((p) => p.name)).toEqual(['prog15'])
})

test('characters that mean something in patterns are plain text', () => {
  expect(filterProcesses(make(5), '.*')).toEqual([])
})

test('the list is read from a reply that was asked for it', () => {
  expect(processesFromReply(reply(), true)?.length).toBe(3)
})

test('a reply asked without the list gives no list at all, not an empty one', () => {
  expect(processesFromReply(reply(), false)).toBeNull()
})

test('a reply with no numbers (old helper, never seen) gives no list', () => {
  expect(processesFromReply(reply({ state: 'old_helper', stats: null }), true)).toBeNull()
})
