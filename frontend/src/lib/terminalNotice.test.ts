import { test, expect } from 'bun:test'
import { QUICK_END_MS, terminalNotice, type Ending } from './terminalNotice.ts'

const refused = (code: string): Ending => ({ kind: 'refused', code })
const closed = (reason: string, openMs: number, typed = false): Ending => ({ kind: 'closed', reason, openMs, typed })
const STOPPED_TEXT = 'This VM has stopped, so there is nothing to connect to.'
const RIGHT_AFTER_TEXT = 'The VM stopped right after it started.'

test('nothing happened, nothing to say', () => {
  expect(terminalNotice(null, 'running')).toBeNull()
})

test('a VM that is not running says it has stopped, with why and a Start button, when the panel knows it is stopped', () => {
  expect(terminalNotice(refused('not_running'), 'stopped')).toEqual({ text: STOPPED_TEXT, why: true, canStart: true })
})

test('the list can be a few seconds old: a VM the parent says is not running but the list shows as running gets plain words and no Start button', () => {
  for (const state of ['running', 'provisioning', 'failed']) {
    expect(terminalNotice(refused('not_running'), state), state).toEqual({ text: 'This VM is not running right now, so there is nothing to connect to.', why: false, canStart: false })
  }
  expect(terminalNotice(refused('not_running'), null)?.canStart).toBe(false)
})

test('the other refusals are said in plain words, and none of them offers Start', () => {
  expect(terminalNotice(refused('not_supported'), 'running')).toEqual({ text: 'Terminals work on Mac machines only for now.', why: false, canStart: false })
  expect(terminalNotice(refused('unreachable'), 'running')).toEqual({ text: 'The machine is offline, so this VM cannot be reached right now.', why: false, canStart: false })
  expect(terminalNotice(refused('too_many_consoles'), 'running')).toEqual({ text: 'Too many terminals are open. Close one and try again.', why: false, canStart: false })
  expect(terminalNotice(refused('console_open'), 'running')).toEqual({ text: 'This VM already has a terminal open. Close it and try again.', why: false, canStart: false })
})

test('a refusal the panel does not know keeps the status line', () => {
  expect(terminalNotice(refused('internal'), 'running')).toBeNull()
})

test('a shell that ends within five seconds of opening means the VM stopped right after it started', () => {
  expect(terminalNotice(closed('the shell ended', 2000), 'stopped')).toEqual({ text: RIGHT_AFTER_TEXT, why: true, canStart: true })
  expect(terminalNotice(closed('the shell ended', QUICK_END_MS - 1), 'running')).toEqual({ text: RIGHT_AFTER_TEXT, why: true, canStart: false })
})

test('a shell that ends soon after the person typed into it is the person leaving: typing exit is not a VM that died', () => {
  expect(terminalNotice(closed('the shell ended', 1000, true), 'running')).toBeNull()
  expect(terminalNotice(closed('the VM stopped', 1000, true), 'stopped')).toEqual({ text: 'This VM has stopped.', why: true, canStart: true })
})

test('a shell that ends later is the person leaving, and the status line says so', () => {
  expect(terminalNotice(closed('the shell ended', QUICK_END_MS), 'running')).toBeNull()
  expect(terminalNotice(closed('the shell ended', 60_000), 'running')).toBeNull()
})

test('when the VM stops under an open terminal the window says so, with why and Start', () => {
  expect(terminalNotice(closed('the VM stopped', 120_000), 'stopped')).toEqual({ text: 'This VM has stopped.', why: true, canStart: true })
  expect(terminalNotice(closed('the VM stopped', 120_000), 'running')).toEqual({ text: 'This VM has stopped.', why: true, canStart: false })
  expect(terminalNotice(closed('the VM stopped', 1000), 'stopped')?.text).toBe(RIGHT_AFTER_TEXT)
})

test('a shell that ends when the list already shows the VM stopped says it has stopped', () => {
  expect(terminalNotice(closed('the shell ended', 90_000), 'stopped')).toEqual({ text: 'This VM has stopped.', why: true, canStart: true })
})

test('a deleted VM and a machine that went offline are said in plain words', () => {
  expect(terminalNotice(closed('the VM was deleted', 5000), null)).toEqual({ text: 'This VM was deleted.', why: false, canStart: false })
  expect(terminalNotice(closed('the machine is offline', 5000), 'running')).toEqual({ text: 'The machine went offline, so the terminal was closed.', why: false, canStart: false })
})

test('the other ways a terminal ends (idle, too long, closed by the person) keep the status line', () => {
  for (const reason of ['idle for 15 minutes', 'the console ran for 8 hours', 'the console was closed', '']) {
    expect(terminalNotice(closed(reason, 30_000), 'running'), reason).toBeNull()
  }
})
