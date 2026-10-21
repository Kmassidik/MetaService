import { expect, test } from 'bun:test'
import { lowerRowCards, lowerRowColumns } from './liveLayout.ts'

test('Disk, Network and GPU share the lower row when the machine has a GPU', () => {
  expect(lowerRowCards(true)).toEqual(['disk', 'network', 'gpu'])
  expect(lowerRowColumns(true)).toBe(3)
})

test('without a GPU, Disk and Network share the row at equal width', () => {
  expect(lowerRowCards(false)).toEqual(['disk', 'network'])
  expect(lowerRowColumns(false)).toBe(2)
})
