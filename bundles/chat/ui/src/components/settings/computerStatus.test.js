import { describe, expect, it } from 'vitest'
import { computerStatusNote } from './computerStatus.js'

describe('computerStatusNote', () => {
  it('describes sleep as a machine action, not finishing Computer control', () => {
    const note = computerStatusNote({ state: 'ready' })
    expect(note).toMatch(/private machine/i)
    expect(note).toMatch(/sleep/i)
    expect(note).not.toMatch(/when you’re done|when you're done/i)
  })
})
