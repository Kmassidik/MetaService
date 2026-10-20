import { expect, test } from 'bun:test'
import { parseErrorDetail } from './errorBody.ts'

test('reads the fields of a refusal', () => {
  const body = { error: { code: 'no_room', message: 'No room', resource: 'ram_mb', needed: 4096, free: 1024 } }
  expect(parseErrorDetail(body)).toEqual({ code: 'no_room', message: 'No room', resource: 'ram_mb', needed: 4096, free: 1024 })
})

test('drops fields of the wrong type', () => {
  expect(parseErrorDetail({ error: { code: 7, message: 'x', needed: '5', free: 1.5 } })).toEqual({ message: 'x' })
})

test('an answer with no error object has no detail', () => {
  expect(parseErrorDetail(null)).toBeUndefined()
  expect(parseErrorDetail([])).toBeUndefined()
  expect(parseErrorDetail({ error: 'text' })).toBeUndefined()
  expect(parseErrorDetail({})).toBeUndefined()
})
