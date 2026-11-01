import { describe, expect, test } from 'bun:test'
import type { SecurityEvent } from './securityTypes.ts'
import { CONNECTION_TOOLTIP, eventDetailText, eventTone, eventTypeLabel, eventTypeTitle, isConnectionCount, isMacOs } from './securityView.ts'

const DETAIL = 'SSH connections (macOS does not log who tried)'
const event = (extra: Partial<SecurityEvent> = {}): SecurityEvent => ({
  id: 'e', time: '2026-11-01T08:47:00Z', machine: 'mac', type: 'failed_login', user: null, address: null, detail: DETAIL, method: null, count: 3322, ...extra,
})

describe('a Mac connection count', () => {
  test('is a failed login with no user, no address and the SSH connections detail', () => {
    expect(isConnectionCount(event())).toBe(true)
    expect(isConnectionCount(event({ detail: 'SSH connections' }))).toBe(true)
  })
  test('is not recognised when anything else differs', () => {
    expect(isConnectionCount(event({ user: 'root' }))).toBe(false)
    expect(isConnectionCount(event({ address: '1.2.3.4' }))).toBe(false)
    expect(isConnectionCount(event({ detail: 'Invalid user' }))).toBe(false)
    expect(isConnectionCount(event({ detail: null }))).toBe(false)
    expect(isConnectionCount(event({ type: 'login' }))).toBe(false)
    expect(isConnectionCount(event({ detail: 'ssh connections' }))).toBe(false)
  })
  test('is named SSH connections, with the tooltip, in the neutral colour', () => {
    expect(eventTypeLabel(event())).toBe('SSH connections')
    expect(eventTypeTitle(event())).toBe(CONNECTION_TOOLTIP)
    expect(eventTone(event())).toBe('')
    expect(eventDetailText(event())).toBe('3,322 connections')
    expect(eventDetailText(event({ count: 1 }))).toBe('1 connection')
  })
  test('a real failed login keeps its wording', () => {
    const real = event({ user: 'root', address: '1.2.3.4', detail: 'Invalid user', count: 5 })
    expect(eventTypeLabel(real)).toBe('Failed login')
    expect(eventTypeTitle(real)).toBeUndefined()
    expect(eventDetailText(real)).toBe('5 tries · Invalid user')
  })
})

test('macOS is told by the os field', () => {
  expect([isMacOs('macos'), isMacOs('Darwin'), isMacOs('linux'), isMacOs('')]).toEqual([true, true, false, false])
})
