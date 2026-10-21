import { test, expect } from 'bun:test'
import { TOP_PROCESSES, visibleProcesses } from './processList.ts'
import type { StatsProcess } from './types.ts'

const make = (count: number): StatsProcess[] => Array.from({ length: count }, (_, index) => ({ pid: index + 1, name: `prog${index + 1}`, user: index % 2 ? 'root' : 'kurnia', cpu_percent: 1, memory_bytes: 1 }))

test('five rows by default, and the total says how many there are', () => {
  const view = visibleProcesses(make(15), '', false)
  expect(view.rows.length).toBe(TOP_PROCESSES)
  expect(view.total).toBe(15)
  expect(view.canExpand).toBe(true)
})

test('show all reveals every row', () => {
  expect(visibleProcesses(make(15), '', true).rows.length).toBe(15)
})

test('a short list has nothing to expand', () => {
  const view = visibleProcesses(make(4), '', false)
  expect(view.rows.length).toBe(4)
  expect(view.canExpand).toBe(false)
})

test('the filter matches name or user as plain text, ignoring case and spaces around it', () => {
  expect(visibleProcesses(make(15), ' PROG1 ', true).rows.map((p) => p.name)).toEqual(['prog1', 'prog10', 'prog11', 'prog12', 'prog13', 'prog14', 'prog15'])
  expect(visibleProcesses(make(15), 'root', true).rows.length).toBe(7)
})

test('the filter searches all rows, not only the first five', () => {
  const view = visibleProcesses(make(15), 'prog15', false)
  expect(view.rows.map((p) => p.name)).toEqual(['prog15'])
  expect(view.canExpand).toBe(false)
})

test('characters that mean something in patterns are plain text', () => {
  expect(visibleProcesses(make(5), '.*', true).rows).toEqual([])
})
