import { describe, expect, it } from 'vitest'
import { composerTrigger, withoutTrigger } from './composerTriggers.js'

describe('composerTrigger', () => {
  it('opens skills when / is the first character', () => {
    expect(composerTrigger('/', 1, '/')).toBe('skill')
  })

  it('keeps / inside text as plain text', () => {
    expect(composerTrigger('a/', 2, '/')).toBe('')
  })

  it('opens mentions for @ at the start or after a space', () => {
    expect(composerTrigger('@', 1, '@')).toBe('mention')
    expect(composerTrigger('hi @', 4, '@')).toBe('mention')
  })

  it('keeps @ inside an e-mail address as plain text', () => {
    expect(composerTrigger('me@', 3, '@')).toBe('')
  })

  it('ignores other characters', () => {
    expect(composerTrigger('a', 1, 'a')).toBe('')
  })
})

describe('withoutTrigger', () => {
  it('removes the character just before the caret', () => {
    expect(withoutTrigger('hi @there', 4)).toBe('hi there')
  })
})
