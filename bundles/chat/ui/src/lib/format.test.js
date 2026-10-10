import { describe, expect, it } from 'vitest'
import { bytes, fail, fileSize, initials } from './format.js'

describe('format helpers', () => {
  it('initials from a name', () => {
    expect(initials('Ada Lovelace')).toBe('AL')
    expect(initials('')).toBe('M')
  })

  it('bytes counts utf8', () => {
    expect(bytes('hi')).toBe(2)
  })

  it('fileSize formats', () => {
    expect(fileSize(512)).toBe('512 B')
    expect(fileSize(2048)).toContain('KiB')
  })

  it('fail reads error message', () => {
    expect(fail(new Error('boom'))).toBe('boom')
    expect(fail({})).toContain('Something went wrong')
  })
})

