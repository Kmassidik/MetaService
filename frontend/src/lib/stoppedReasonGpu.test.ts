import { expect, test } from 'bun:test'
import { readStoppedReason } from './stoppedReason.ts'

const OVER_LIMIT = { code: 'gpu_memory_over_limit', message: 'It used 6 GB of GPU memory; its limit is 4 GB.', used_gb: 6, limit_gb: 4 }

test('a reason with a code may leave out the exit code and the log, and keeps its message', () => {
  expect(readStoppedReason(OVER_LIMIT)).toEqual({ exit_code: null, log_tail: '', ...OVER_LIMIT })
  expect(readStoppedReason({ ...OVER_LIMIT, exit_code: null, log_tail: '' })).toEqual({ exit_code: null, log_tail: '', ...OVER_LIMIT })
})

test('a named reason still rejects an exit code or log of the wrong type, and checks the numbers', () => {
  expect(readStoppedReason({ ...OVER_LIMIT, exit_code: '1' })).toBeNull()
  expect(readStoppedReason({ ...OVER_LIMIT, log_tail: 5 })).toBeNull()
  expect(readStoppedReason({ ...OVER_LIMIT, used_gb: 'six', limit_gb: undefined })).toEqual({ exit_code: null, log_tail: '', code: OVER_LIMIT.code, message: OVER_LIMIT.message, used_gb: null, limit_gb: null })
})

test('a reason without a code is still rejected when it leaves out a field, and gains no extra keys', () => {
  expect(readStoppedReason({ exit_code: 1 })).toBeNull()
  expect(Object.keys(readStoppedReason({ exit_code: 1, log_tail: 'x' }) ?? {})).toEqual(['exit_code', 'log_tail'])
})

test('the message of a named reason is cleaned and stays text', () => {
  const reason = readStoppedReason({ ...OVER_LIMIT, message: '\u001b[31m<img src=x onerror=alert(1)>\u0007' })
  expect(reason?.message).toBe('<img src=x onerror=alert(1)>')
})
