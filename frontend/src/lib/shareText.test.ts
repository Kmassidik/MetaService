import { expect, test } from 'bun:test'
import type { OsChoice } from './share.ts'
import { choosable, cpuNote, handshakeText, NO_SYSTEM_NOTE, removePeerCopy, saneName, stateText, timeLeft } from './shareText.ts'

const mac: OsChoice = { os: 'mac', cpus: [{ cpu: 'arm64', state: 'ready' }, { cpu: 'x86_64', state: 'untested' }] }
const windows: OsChoice = { os: 'windows', cpus: [{ cpu: 'arm64', state: 'missing' }, { cpu: 'x86_64', state: 'soon' }] }

test('each build state has its own tag and tone', () => {
  expect(stateText('ready')).toMatchObject({ tag: 'ready', tone: 'run', why: '' })
  expect(stateText('untested')).toMatchObject({ tag: 'not tested yet', tone: 'warn' })
  expect(stateText('missing')).toMatchObject({ tag: 'no build yet', tone: '' })
  expect(stateText('soon')).toMatchObject({ tag: 'coming soon', tone: '' })
})

test('only a ready or an untested build can be chosen', () => {
  expect((['ready', 'untested', 'missing', 'soon'] as const).map(choosable)).toEqual([true, true, false, false])
})

test('the note under the CPU choices explains the chosen one, else why the others are off, else asks for a system', () => {
  expect(cpuNote(undefined, '')).toBe(NO_SYSTEM_NOTE)
  expect(cpuNote(mac, 'arm64')).toBe('')
  expect(cpuNote(mac, 'x86_64')).toContain('may not work')
  expect(cpuNote(mac, '')).toBe('')
  expect(cpuNote(windows, '')).toBe('Apple silicon / ARM (arm64) and Intel / AMD (x86_64): There is no helper build for this computer yet.')
})

test('time left reads in seconds, then minutes, and says expired', () => {
  const now = Date.parse('2026-10-31T10:00:00Z')
  expect(timeLeft('2026-10-31T10:00:42Z', now)).toBe('42 s left')
  expect(timeLeft('2026-10-31T10:12:00Z', now)).toBe('12 min left')
  expect(timeLeft('2026-10-31T09:59:00Z', now)).toBe('expired')
  expect(timeLeft('not a time', now)).toBe('')
})

test('the last handshake reads in seconds, minutes or hours, and never', () => {
  expect([null, 5, 89, 120, 5400, 7200].map(handshakeText)).toEqual(['never', '5 s ago', '89 s ago', '2 min ago', '2 h ago', '2 h ago'])
})

test('a host name becomes a safe machine name', () => {
  expect(saneName("Kurnia's MacBook Pro.local")).toBe('kurnia-s-macbook-pro.local')
  expect(saneName('<img src=x>')).toBe('img-src-x')
  expect(saneName('***')).toBe('far-pc')
  expect(saneName('')).toBe('far-pc')
})

test('the remove question names the machine and what is lost', () => {
  const copy = removePeerCopy({ name: 'far-mac' })
  expect(copy.what).toContain('far-mac')
  expect(copy.confirmLabel).toBe('Remove machine')
})
