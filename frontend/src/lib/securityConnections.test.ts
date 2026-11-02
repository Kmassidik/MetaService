import { describe, expect, test } from 'bun:test'
import type { SecurityEvent } from './securityTypes.ts'
import type { MachineInfo } from './securityView.ts'
import { CONNECTION_TOOLTIP, eventDetailText, eventTone, eventTypeLabel, eventTypeTitle, isConnectionCount, isMacOs } from './securityView.ts'

const OLD_DETAIL = 'SSH connections (macOS does not log who tried)'
const MAC: MachineInfo = { id: 'mac', name: 'Mac Studio', state: 'online', os: 'macos' }
const LINUX: MachineInfo = { id: 'box', name: 'RTX PC', state: 'online', os: 'linux' }
const INFOS = [MAC, LINUX]
/** What the real parent sends for a Mac: no user, no address and no detail (it stores none for failed logins). */
const event = (extra: Partial<SecurityEvent> = {}): SecurityEvent => ({
  id: 'e', time: '2026-11-01T08:47:00Z', machine: 'mac', type: 'failed_login', user: null, address: null, detail: null, method: null, count: 3322, ...extra,
})

describe('a Mac connection count', () => {
  test('is a failed login with no user and no address from a Mac, even with no detail', () => {
    expect(isConnectionCount(event(), INFOS)).toBe(true)
    expect(isConnectionCount(event({ detail: OLD_DETAIL }), INFOS)).toBe(true)
  })
  test('old data with the detail is still recognised when the machine is unknown', () => {
    expect(isConnectionCount(event({ machine: 'gone', detail: OLD_DETAIL }), INFOS)).toBe(true)
    expect(isConnectionCount(event({ machine: 'gone' }), INFOS)).toBe(false)
  })
  test('is not recognised when anything else differs', () => {
    expect(isConnectionCount(event({ user: 'root' }), INFOS)).toBe(false)
    expect(isConnectionCount(event({ address: '1.2.3.4' }), INFOS)).toBe(false)
    expect(isConnectionCount(event({ type: 'login' }), INFOS)).toBe(false)
    expect(isConnectionCount(event({ machine: 'box' }), INFOS)).toBe(false)
    expect(isConnectionCount(event({ machine: 'box', detail: 'ssh connections' }), INFOS)).toBe(false)
  })
  test('is named SSH connections, with the tooltip, in the neutral colour', () => {
    expect(eventTypeLabel(event(), INFOS)).toBe('SSH connections')
    expect(eventTypeTitle(event(), INFOS)).toBe(CONNECTION_TOOLTIP)
    expect(eventTone(event(), INFOS)).toBe('')
    expect(eventDetailText(event(), INFOS)).toBe('3,322 connections')
    expect(eventDetailText(event({ count: 1 }), INFOS)).toBe('1 connection')
  })
  test('a real failed login keeps its wording', () => {
    const real = event({ machine: 'box', user: 'root', address: '1.2.3.4', detail: 'Invalid user', count: 5 })
    expect(eventTypeLabel(real, INFOS)).toBe('Failed login')
    expect(eventTypeTitle(real, INFOS)).toBeUndefined()
    expect(eventDetailText(real, INFOS)).toBe('5 tries · Invalid user')
  })
  test('a Linux row with no user and no address stays a failed login', () => {
    expect(eventTypeLabel(event({ machine: 'box' }), INFOS)).toBe('Failed login')
    expect(eventDetailText(event({ machine: 'box', count: 2 }), INFOS)).toBe('2 tries')
  })
})

test('macOS is told by the os field', () => {
  expect([isMacOs('macos'), isMacOs('Darwin'), isMacOs('linux'), isMacOs('')]).toEqual([true, true, false, false])
})
