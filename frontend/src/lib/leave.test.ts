import { expect, test } from 'bun:test'
import { cleanReady, isSharedMachine } from './leave.ts'

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
