import { expect, test } from 'bun:test'
import { firstPickable, isMenuKey, nextActive } from './menuNav.ts'

const flags = [false, true, false, true, false]

test('the arrow keys move to the next line that can be picked and stop at the ends', () => {
  expect(nextActive(flags, 0, 'ArrowDown')).toBe(2)
  expect(nextActive(flags, 2, 'ArrowDown')).toBe(4)
  expect(nextActive(flags, 4, 'ArrowDown')).toBe(4)
  expect(nextActive(flags, 4, 'ArrowUp')).toBe(2)
  expect(nextActive(flags, 0, 'ArrowUp')).toBe(0)
})

test('Home and End go to the first and the last line that can be picked', () => {
  expect(nextActive([true, false, false, true], 2, 'Home')).toBe(1)
  expect(nextActive([true, false, false, true], 1, 'End')).toBe(2)
})

test('with nothing to pick the cursor stays', () => {
  expect(nextActive([true, true], 1, 'ArrowDown')).toBe(1)
  expect(firstPickable([true, true])).toBe(0)
  expect(firstPickable([true, false])).toBe(1)
})

test('only the four moving keys are menu keys', () => {
  expect(['ArrowDown', 'ArrowUp', 'Home', 'End'].every(isMenuKey)).toBe(true)
  expect(isMenuKey('Enter')).toBe(false)
})
