import { test } from 'node:test'
import assert from 'node:assert/strict'
import { MAX_EVENTS, batch, buttonName, macKeyCode, pointerPosition, scrollSteps } from './screen.ts'
import type { ScreenInput } from './types.ts'

test('a pointer inside the picture maps to ten-thousandths, outside it sticks to the edge', () => {
  const box = { left: 100, top: 50, width: 400, height: 200 }
  assert.deepEqual(pointerPosition(300, 150, box), { x: 5000, y: 5000 })
  assert.deepEqual(pointerPosition(100, 50, box), { x: 0, y: 0 })
  assert.deepEqual(pointerPosition(900, 900, box), { x: 10000, y: 10000 })
  assert.deepEqual(pointerPosition(0, 0, box), { x: 0, y: 0 })
  assert.deepEqual(pointerPosition(5, 5, { left: 0, top: 0, width: 0, height: 0 }), { x: 0, y: 0 })
})

test('keys map to Mac virtual key codes and unknown keys are left out', () => {
  assert.equal(macKeyCode('KeyA'), 0)
  assert.equal(macKeyCode('Enter'), 36)
  assert.equal(macKeyCode('ArrowUp'), 126)
  assert.equal(macKeyCode('IntlBackslash'), null)
})

test('every key code is a valid Agent key code', () => {
  for (const code of ['KeyA', 'KeyZ', 'Digit0', 'Space', 'ArrowUp', 'F12', 'MetaLeft']) {
    const value = macKeyCode(code)
    assert.ok(value !== null && value >= 0 && value <= 127, code)
  }
})

test('wheel movement becomes bounded scroll steps, inverted for the Mac', () => {
  assert.deepEqual(scrollSteps(0, 120), { dx: 0, dy: -3 })
  assert.deepEqual(scrollSteps(-80, 0), { dx: 2, dy: 0 })
  assert.deepEqual(scrollSteps(0, 100000), { dx: 0, dy: -50 })
})

test('mouse buttons', () => {
  assert.deepEqual([0, 1, 2, 7].map(buttonName), ['left', 'middle', 'right', 'left'])
})

test('a batch keeps only the last move and never more than one call may carry', () => {
  const events: ScreenInput[] = [{ type: 'move', x: 1, y: 1 }, { type: 'button', button: 'left', down: true }, { type: 'move', x: 2, y: 2 }, { type: 'move', x: 3, y: 3 }]
  assert.deepEqual(batch(events), [{ type: 'button', button: 'left', down: true }, { type: 'move', x: 3, y: 3 }])
  const many: ScreenInput[] = Array.from({ length: 200 }, (_, index) => ({ type: 'key', code: index % 100, down: true }))
  assert.equal(batch(many).length, MAX_EVENTS)
})
