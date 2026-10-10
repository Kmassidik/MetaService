import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { SAVED_FLASH_MS, createSavedFlash } from './savedFlash.js'

describe('saved tick timing', () => {
  let shown
  let flash

  beforeEach(() => {
    vi.useFakeTimers()
    shown = {}
    flash = createSavedFlash((key, on) => { shown[key] = on })
  })

  afterEach(() => vi.useRealTimers())

  it('shows at once and hides itself after SAVED_FLASH_MS', () => {
    flash.show('details')
    expect(shown.details).toBe(true)
    vi.advanceTimersByTime(SAVED_FLASH_MS - 1)
    expect(shown.details).toBe(true)
    vi.advanceTimersByTime(1)
    expect(shown.details).toBe(false)
  })

  it('is about two seconds', () => {
    expect(SAVED_FLASH_MS).toBe(2000)
  })

  it('restarts its timer when shown again', () => {
    flash.show('label')
    vi.advanceTimersByTime(SAVED_FLASH_MS - 500)
    flash.show('label')
    vi.advanceTimersByTime(SAVED_FLASH_MS - 1)
    expect(shown.label).toBe(true)
    vi.advanceTimersByTime(1)
    expect(shown.label).toBe(false)
  })

  it('times each control on its own', () => {
    flash.show('avatar')
    vi.advanceTimersByTime(SAVED_FLASH_MS / 2)
    flash.show('skills')
    vi.advanceTimersByTime(SAVED_FLASH_MS / 2)
    expect(shown).toEqual({ avatar: false, skills: true })
  })

  it('hide turns it off early and cancels its timer', () => {
    const onChange = vi.fn()
    const own = createSavedFlash(onChange)
    own.show('more')
    own.hide('more')
    vi.advanceTimersByTime(SAVED_FLASH_MS)
    expect(onChange.mock.calls).toEqual([['more', true], ['more', false]])
  })
})
