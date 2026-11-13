import { expect, test } from 'bun:test'
import { panelStatusOf } from './netStatus.ts'

test('nothing read yet is loading, or failed when the ask failed', () => {
  expect(panelStatusOf(null, false)).toBe('loading')
  expect(panelStatusOf(null, true)).toBe('failed')
})

test('no readings is empty, or failed when the ask failed', () => {
  expect(panelStatusOf(0, false)).toBe('empty')
  expect(panelStatusOf(0, true)).toBe('failed')
})

test('readings show the chart, or the chart with the last numbers when the newest ask failed', () => {
  expect(panelStatusOf(5, false)).toBe('ready')
  expect(panelStatusOf(5, true)).toBe('stale')
})
