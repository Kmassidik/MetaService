import { expect, test } from 'bun:test'
import { ApiError } from './api.ts'
import { cleanReady, isCannotClean, isSharedMachine, notCleanedNote } from './leave.ts'

test('only a machine on the shared network is a Share a PC machine', () => {
  expect(isSharedMachine({ ip: '10.77.0.2' })).toBe(true)
  expect(isSharedMachine({ ip: '192.168.0.40' })).toBe(false)
  expect(isSharedMachine({ ip: '202.51.196.202' })).toBe(false)
  expect(isSharedMachine({})).toBe(false)
})

test('the clean-up needs the password only when it is asked for', () => {
  expect(cleanReady(true, '')).toBe(false)
  expect(cleanReady(true, 'secret')).toBe(true)
  expect(cleanReady(false, '')).toBe(true)
})

test('a helper too old to clean itself is not a dead end, a wrong password still is', () => {
  expect(isCannotClean(new ApiError(409, 'old_helper', 'too old'))).toBe(true)
  expect(isCannotClean(new ApiError(409, 'not_joined', 'never joined'))).toBe(true)
  expect(isCannotClean(new ApiError(409, 'leave_failed', 'sudo did not accept the password'))).toBe(false)
  expect(isCannotClean(new Error('network'))).toBe(false)
  expect(notCleanedNote('fedora')).toContain('Leave that join first')
})
