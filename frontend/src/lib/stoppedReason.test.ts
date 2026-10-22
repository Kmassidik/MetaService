import { test, expect } from 'bun:test'
import { exitCodeText, isPlainMode, reasonNote, MAX_REASON_BYTES, MAX_REASON_LINES, PLAIN_MODE_TEXT, readStoppedReason, stopNote, stopNoteText } from './stoppedReason.ts'
import { command, workload } from './testing.ts'

const REASON = { exit_code: 255, log_tail: 'Failed to mount API filesystems.\nExiting PID 1...' }
const stopped = (extra = {}) => workload({ id: 'w-1', state: 'stopped', ...extra })

test('a reason in the promised shape is read as it is', () => {
  expect(readStoppedReason(REASON)).toEqual(REASON)
  expect(readStoppedReason({ exit_code: null, log_tail: '' })).toEqual({ exit_code: null, log_tail: '' })
})

test('anything else is no reason', () => {
  for (const junk of [null, undefined, 'boom', 7, [], {}, { log_tail: 'x' }, { exit_code: '1', log_tail: 'x' }, { exit_code: 1.5, log_tail: 'x' }, { exit_code: 1, log_tail: 5 }]) {
    expect(readStoppedReason(junk), JSON.stringify(junk)).toBeNull()
  }
})

test('control characters and escape sequences are removed again, and markup stays the same text', () => {
  const reason = readStoppedReason({ exit_code: 1, log_tail: '\u001b[31m<img src=x onerror=alert(1)>\u001b[0m\u0000\u0007 ok\r\nnext\tline' })
  expect(reason?.log_tail).toBe('<img src=x onerror=alert(1)> ok\nnext line')
})

test('the text is cut to the last lines and the size the parent promised', () => {
  const lines = Array.from({ length: 40 }, (_, index) => `line ${index + 1}`).join('\n')
  const tail = readStoppedReason({ exit_code: 1, log_tail: lines })?.log_tail ?? ''
  expect(tail.split('\n')).toHaveLength(MAX_REASON_LINES)
  expect(tail.endsWith('line 40')).toBe(true)
  const long = readStoppedReason({ exit_code: 1, log_tail: 'é'.repeat(5000) })?.log_tail ?? ''
  expect(new TextEncoder().encode(long).length).toBeLessThanOrEqual(MAX_REASON_BYTES)
})

test('the exit code is said in words', () => {
  expect(exitCodeText(255)).toBe('Exit code 255.')
  expect(exitCodeText(0)).toBe('Exit code 0.')
  expect(exitCodeText(null)).toBe('The exit code is not known.')
})

test('a stopped VM with a reason shows the reason', () => {
  expect(stopNote('m', stopped({ stopped_reason: REASON }), [])).toEqual({ kind: 'reason', reason: REASON })
})

test('a stopped VM without a reason says it was stopped only when the panel stopped it last', () => {
  const stop = command({ id: 'c2', type: 'stop', workload_id: 'w-1', state: 'succeeded', created_at: '2026-01-01T00:05:00Z' })
  expect(stopNote('m', stopped(), [stop])).toEqual({ kind: 'panel' })
  expect(stopNoteText({ kind: 'panel' })).toBe('It was stopped.')
  const startAfter = command({ id: 'c3', type: 'start', workload_id: 'w-1', state: 'succeeded', created_at: '2026-01-01T00:06:00Z' })
  expect(stopNote('m', stopped(), [stop, startAfter])).toEqual({ kind: 'own' })
  expect(stopNote('m', stopped(), [startAfter, stop])).toEqual({ kind: 'own' })
})

test('without a stop order of the panel, the VM stopped on its own and the words do not claim a reason', () => {
  expect(stopNote('m', stopped(), [])).toEqual({ kind: 'own' })
  expect(stopNoteText({ kind: 'own' })).toBe('It stopped on its own; the machine did not say why yet.')
  const failed = command({ type: 'stop', workload_id: 'w-1', state: 'failed' })
  const otherVm = command({ type: 'stop', workload_id: 'w-9', state: 'succeeded' })
  const otherMachine = command({ type: 'stop', workload_id: 'w-1', state: 'succeeded', machine: 'elsewhere' })
  expect(stopNote('m', stopped(), [failed, otherVm, otherMachine])).toEqual({ kind: 'own' })
})

test('a VM that is not stopped has nothing to explain', () => {
  expect(stopNote('m', workload({ state: 'running' }), [])).toBeNull()
  expect(stopNote('m', workload({ state: 'provisioning' }), [])).toBeNull()
})

test('a failed VM shows its reason when it has one and is otherwise left alone', () => {
  expect(stopNote('m', workload({ state: 'failed', stopped_reason: REASON }), [])).toEqual({ kind: 'reason', reason: REASON })
  expect(stopNote('m', workload({ state: 'failed' }), [])).toBeNull()
})

test('a reason that is not in the promised shape is treated as no reason', () => {
  expect(stopNote('m', stopped({ stopped_reason: { exit_code: 'x' } }), [])).toEqual({ kind: 'own' })
})

test('a reason alone makes a note for the compact rows, and no reason makes none', () => {
  expect(reasonNote(REASON)).toEqual({ kind: 'reason', reason: REASON })
  expect(reasonNote(null)).toBeNull()
})

test('only a plain VM gets the note about missing systemd', () => {
  expect(isPlainMode(workload({ init_mode: 'plain' }))).toBe(true)
  const others: ('systemd' | null)[] = ['systemd', null]
  for (const mode of others) expect(isPlainMode(workload({ init_mode: mode })), String(mode)).toBe(false)
  expect(isPlainMode(workload())).toBe(false)
  expect(PLAIN_MODE_TEXT).toBe('This VM runs without systemd (a system service manager). A terminal works; services like systemd do not.')
})
