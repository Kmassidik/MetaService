import { describe, expect, it } from 'vitest'
import { SWIPE_MIN_PX, clampIndex, counterLabel, keyStep, stepIndex, swipeStep } from './viewerNav.js'

describe('viewer navigation', () => {
  it('steps between pictures and stops at both ends', () => {
    expect(stepIndex(0, 1, 3)).toBe(1)
    expect(stepIndex(2, 1, 3)).toBe(2)
    expect(stepIndex(0, -1, 3)).toBe(0)
    expect(stepIndex(1, -1, 3)).toBe(0)
  })

  it('keeps an index inside the list, even an empty one', () => {
    expect(clampIndex(7, 3)).toBe(2)
    expect(clampIndex(-2, 3)).toBe(0)
    expect(clampIndex(4, 0)).toBe(0)
  })

  it('maps the arrow keys and ignores others', () => {
    expect(keyStep('ArrowRight')).toBe(1)
    expect(keyStep('ArrowLeft')).toBe(-1)
    expect(keyStep('ArrowUp')).toBe(0)
    expect(keyStep('Enter')).toBe(0)
  })

  it('turns a horizontal swipe into a step, like a photo app', () => {
    expect(swipeStep(-SWIPE_MIN_PX, 0)).toBe(1)
    expect(swipeStep(SWIPE_MIN_PX + 20, 10)).toBe(-1)
  })

  it('ignores short or mostly vertical drags', () => {
    expect(swipeStep(-(SWIPE_MIN_PX - 1), 0)).toBe(0)
    expect(swipeStep(-80, 120)).toBe(0)
  })

  it('counts from one', () => {
    expect(counterLabel(0, 3)).toBe('1 of 3')
  })
})
