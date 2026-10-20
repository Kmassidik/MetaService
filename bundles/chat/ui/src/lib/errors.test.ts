import { describe, expect, it } from 'bun:test'
import { ApiError, errorMessage, errorName, errorStatus } from './errors.ts'

describe('error readers', () => {
  it('read an ApiError', () => {
    const error = new ApiError('Not found', 404)
    expect(errorStatus(error)).toBe(404)
    expect(errorName(error)).toBe('ApiError')
    expect(errorMessage(error)).toBe('Not found')
  })

  it('read a plain Error without a status', () => {
    const error = new Error('boom')
    expect(errorStatus(error)).toBeUndefined()
    expect(errorName(error)).toBe('Error')
    expect(errorMessage(error)).toBe('boom')
  })

  it('give empty answers for values that are not objects', () => {
    for (const value of [null, undefined, 'text', 5, []]) {
      expect(errorStatus(value)).toBeUndefined()
      expect(errorName(value)).toBe('')
      expect(errorMessage(value)).toBe('')
    }
  })

  it('ignore fields of the wrong type', () => {
    expect(errorStatus({ status: '500' })).toBeUndefined()
    expect(errorName({ name: 1 })).toBe('')
    expect(errorMessage({ message: {} })).toBe('')
  })
})
