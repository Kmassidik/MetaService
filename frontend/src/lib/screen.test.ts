import { test, expect } from 'bun:test'
import { MAX_EVENTS, batch, buttonName, macKeyCode, pointerPosition, scrollSteps } from './screen.ts'
import type { ScreenInput } from './types.ts'

test('a pointer inside the picture maps to ten-thousandths, outside it sticks to the edge', () => {
  const box = { left: 100, top: 50, width: 400, height: 200 }
  expect(pointerPosition(300, 150, box)).toEqual({ x: 5000, y: 5000 })
  expect(pointerPosition(100, 50, box)).toEqual({ x: 0, y: 0 })
  expect(pointerPosition(900, 900, box)).toEqual({ x: 10000, y: 10000 })
  expect(pointerPosition(0, 0, box)).toEqual({ x: 0, y: 0 })
  expect(pointerPosition(5, 5, { left: 0, top: 0, width: 0, height: 0 })).toEqual({ x: 0, y: 0 })
})

test('keys map to Mac virtual key codes and unknown keys are left out', () => {
  expect(macKeyCode('KeyA')).toBe(0)
  expect(macKeyCode('Enter')).toBe(36)
  expect(macKeyCode('ArrowUp')).toBe(126)
  expect(macKeyCode('IntlBackslash')).toBe(null)
})

test('every key code is a valid Agent key code', () => {
  for (const code of ['KeyA', 'KeyZ', 'Digit0', 'Space', 'ArrowUp', 'F12', 'MetaLeft']) {
    const value = macKeyCode(code)
    expect(value !== null && value >= 0 && value <= 127).toBeTruthy()
  }
})

test('wheel movement becomes bounded scroll steps, inverted for the Mac', () => {
  expect(scrollSteps(0, 120)).toEqual({ dx: 0, dy: -3 })
  expect(scrollSteps(-80, 0)).toEqual({ dx: 2, dy: 0 })
  expect(scrollSteps(0, 100000)).toEqual({ dx: 0, dy: -50 })
})

test('mouse buttons', () => {
  expect([0, 1, 2, 7].map(buttonName)).toEqual(['left', 'middle', 'right', 'left'])
})

test('a batch keeps only the last move and never more than one call may carry', () => {
  const events: ScreenInput[] = [{ type: 'move', x: 1, y: 1 }, { type: 'button', button: 'left', down: true }, { type: 'move', x: 2, y: 2 }, { type: 'move', x: 3, y: 3 }]
  expect(batch(events)).toEqual([{ type: 'button', button: 'left', down: true }, { type: 'move', x: 3, y: 3 }])
  const many: ScreenInput[] = Array.from({ length: 200 }, (_, index) => ({ type: 'key', code: index % 100, down: true }))
  expect(batch(many).length).toBe(MAX_EVENTS)
})
