import { test, expect } from 'bun:test'
import { mergeOrders, parseCommand, pendingFor, pendingVms, reasonText, stageSteps, stageText, type PendingVm } from './pendingVms.ts'
import { MAX_FAILURE_BYTES, MAX_FAILURE_LINES } from './stoppedReason.ts'
import { command, machine, workload } from './testing.ts'

const NOW = Date.parse('2026-01-01T00:10:00Z')
const SECOND = 1000
const MINUTE = 60 * SECOND
const iso = (ms: number) => new Date(ms).toISOString()
const none = new Set<string>()
const box = machine({ id: 'm', name: 'Studio' })
const order = (extra: Parameters<typeof command>[0] = {}) => command({ id: 'c1', params: { name: 'test' }, created_at: iso(NOW - 5 * SECOND), ...extra })

test('a queued order is a VM waiting for its machine, a running one is being created, a succeeded one not yet listed is starting', () => {
  expect(pendingVms([order({ state: 'queued' })], [box], NOW, none).map((entry) => entry.stage)).toEqual(['waiting'])
  expect(pendingVms([order({ state: 'running' })], [box], NOW, none).map((entry) => entry.stage)).toEqual(['creating'])
  expect(pendingVms([order({ state: 'succeeded', result: { workload_id: 'w-1' }, finished_at: iso(NOW - 2 * SECOND) })], [box], NOW, none).map((entry) => entry.stage)).toEqual(['starting'])
})

test('a pending VM carries its name and the machine it is going to', () => {
  expect(pendingVms([order({ state: 'queued' })], [box], NOW, none)[0]).toMatchObject({ id: 'c1', name: 'test', machine: 'm', machineName: 'Studio', reason: null })
})

test('only create orders count: start, stop and delete are not new VMs', () => {
  const others = ['start', 'stop', 'delete', 'bundle_install'].map((type, index) => order({ id: `o${index}`, type, state: 'running' }))
  expect(pendingVms(others, [box], NOW, none)).toEqual([])
})

test('the VM leaves the pending list once its machine lists it, by id when the order knows it', () => {
  const done = order({ state: 'succeeded', result: { workload_id: 'w-1' }, finished_at: iso(NOW - SECOND) })
  const listed = machine({ id: 'm', name: 'Studio', workloads: [workload({ id: 'w-1', name: 'test', state: 'stopped' })] })
  expect(pendingVms([done], [listed], NOW, none)).toEqual([])
  const otherVmWithSameName = machine({ id: 'm', name: 'Studio', workloads: [workload({ id: 'w-0', name: 'test' })] })
  expect(pendingVms([done], [otherVmWithSameName], NOW, none)).toHaveLength(1)
})

test('while the order still runs, a VM of that name that is being made on the machine is the same VM', () => {
  const making = machine({ id: 'm', name: 'Studio', workloads: [workload({ id: 'w-5', name: 'test', state: 'provisioning' })] })
  expect(pendingVms([order({ state: 'running' })], [making], NOW, none)).toEqual([])
  const old = machine({ id: 'm', name: 'Studio', workloads: [workload({ id: 'w-0', name: 'test', state: 'running' })] })
  expect(pendingVms([order({ state: 'running' })], [old], NOW, none)).toHaveLength(1)
})

test('a succeeded order the machine never listed stops showing after a few minutes', () => {
  const long = order({ state: 'succeeded', result: { workload_id: 'w-1' }, finished_at: iso(NOW - 6 * MINUTE) })
  expect(pendingVms([long], [box], NOW, none)).toEqual([])
})

test('a VM that was made and then deleted does not come back as pending', () => {
  const done = order({ state: 'succeeded', result: { workload_id: 'w-1' }, finished_at: iso(NOW - 2 * MINUTE) })
  const removal = command({ id: 'c2', type: 'delete', state: 'succeeded', workload_id: 'w-1', created_at: iso(NOW - MINUTE) })
  expect(pendingVms([done, removal], [box], NOW, none)).toEqual([])
  const otherRemoval = command({ id: 'c3', type: 'delete', state: 'succeeded', workload_id: 'w-9', created_at: iso(NOW - MINUTE) })
  expect(pendingVms([done, otherRemoval], [box], NOW, none)).toHaveLength(1)
})

test('a failed order stays with its reason until it is dismissed or old', () => {
  const failed = order({ state: 'failed', result: { error: 'no space left' }, finished_at: iso(NOW - MINUTE) })
  expect(pendingVms([failed], [box], NOW, none)[0]).toMatchObject({ stage: 'failed', reason: 'No space left.' })
  expect(pendingVms([failed], [box], NOW, new Set(['c1']))).toEqual([])
  expect(pendingVms([order({ state: 'failed', created_at: iso(NOW - 60 * MINUTE), finished_at: iso(NOW - 59 * MINUTE) })], [box], NOW, none)).toEqual([])
})

test('an order for a machine that is gone is not shown unless it failed', () => {
  expect(pendingVms([order({ state: 'running', machine: 'gone' })], [box], NOW, none)).toEqual([])
  expect(pendingVms([order({ state: 'failed', machine: 'gone', finished_at: iso(NOW) })], [box], NOW, none)[0]?.machineName).toBe('gone')
})

test('an order that takes very long is marked slow and says what that means', () => {
  const quick = pendingVms([order({ state: 'running', created_at: iso(NOW - MINUTE) })], [box], NOW, none)[0]
  const slow = pendingVms([order({ state: 'running', created_at: iso(NOW - 4 * MINUTE) })], [box], NOW, none)[0]
  expect(quick?.note).toBeNull()
  expect(slow?.note).toBe('This is taking longer than usual. The machine is still working on it.')
  const waiting = pendingVms([order({ state: 'queued', created_at: iso(NOW - 4 * MINUTE) })], [box], NOW, none)[0]
  expect(waiting?.note).toBe('Still waiting for the machine. It may be busy or offline.')
  const unreported = pendingVms([order({ state: 'succeeded', result: { workload_id: 'w-1' }, created_at: iso(NOW - 3 * MINUTE), finished_at: iso(NOW - 2 * MINUTE) })], [box], NOW, none)[0]
  expect(unreported?.note).toBe('The machine has made it but has not reported it yet. It will show here by itself.')
})

test('the newest pending VM comes first', () => {
  const entries = pendingVms([order({ id: 'old', state: 'running', created_at: iso(NOW - 30 * SECOND) }), order({ id: 'new', state: 'queued', created_at: iso(NOW - SECOND) })], [box], NOW, none)
  expect(entries.map((entry) => entry.id)).toEqual(['new', 'old'])
})

test('the same order from the list and from this session counts once, and the list is the fresher one', () => {
  const merged = mergeOrders([order({ state: 'running' })], [order({ state: 'queued' }), order({ id: 'c2', state: 'queued' })])
  expect(merged.map((entry) => [entry.id, entry.state])).toEqual([['c1', 'running'], ['c2', 'queued']])
})

test('the pending VMs of one machine, or of all', () => {
  const entries: PendingVm[] = [{ id: 'a', machine: 'm', machineName: 'M', name: 'a', stage: 'creating', reason: null, note: null }, { id: 'b', machine: 'n', machineName: 'N', name: 'b', stage: 'creating', reason: null, note: null }]
  expect(pendingFor(entries, 'm').map((entry) => entry.id)).toEqual(['a'])
  expect(pendingFor(entries, null)).toHaveLength(2)
})

test('the words and the three steps of each stage', () => {
  expect([stageText('waiting'), stageText('creating'), stageText('starting'), stageText('failed')]).toEqual(['Waiting for the machine', 'Creating', 'Starting', 'Could not make the VM'])
  expect(stageSteps('waiting')).toEqual(['now', 'next', 'next'])
  expect(stageSteps('creating')).toEqual(['done', 'now', 'next'])
  expect(stageSteps('starting')).toEqual(['done', 'done', 'now'])
  expect(stageSteps('failed')).toEqual(['next', 'next', 'next'])
})

test('a reason is a sentence, and a missing one still says something plain', () => {
  expect(reasonText({ error: 'the machine could not create the workload' })).toBe('The machine could not create the workload.')
  expect(reasonText({ error: 'Out of room.' })).toBe('Out of room.')
  expect(reasonText(null)).toBe('The machine could not make the VM.')
  expect(reasonText({})).toBe('The machine could not make the VM.')
})

test('a long reason from the machine keeps its lines, gets no full stop on a log line, and is cleaned and capped again', () => {
  const error = 'The VM did not start.\nTry 1, with systemd: it stopped right after it started (exit code 255). Its last lines:\nFailed to mount API filesystems.\u001b[31m<b>x</b>\u001b[0m\u0000'
  const text = reasonText({ error })
  expect(text).toBe('The VM did not start.\nTry 1, with systemd: it stopped right after it started (exit code 255). Its last lines:\nFailed to mount API filesystems.<b>x</b>')
  const huge = reasonText({ error: Array.from({ length: 200 }, (_, index) => `line ${index}`).join('\n') })
  expect(huge.split('\n').length).toBeLessThanOrEqual(MAX_FAILURE_LINES)
  expect(new TextEncoder().encode(reasonText({ error: 'é'.repeat(9000) })).length).toBeLessThanOrEqual(MAX_FAILURE_BYTES)
})

test('the parent\'s answer to a create is read into an order, and anything else is refused', () => {
  const answer = { command: { id: 'c9', type: 'create', machine: 'm', state: 'queued', created_at: '2026-01-01T00:00:00Z', params: { name: 'x' } } }
  expect(parseCommand(answer)).toMatchObject({ id: 'c9', machine: 'm', state: 'queued', params: { name: 'x' } })
  const deleteAnswer = { command: { ...answer.command, type: 'delete', workload_id: 'w9', result: { error: 'backup failed', backup_id: 'b9' } } }
  expect(parseCommand(deleteAnswer)).toMatchObject({ type: 'delete', workload_id: 'w9', result: { error: 'backup failed', backup_id: 'b9' } })
  for (const bad of [null, 'x', {}, { command: null }, { command: { id: 'c9' } }, { command: { id: 3, machine: 'm', type: 'create', state: 'queued' } }]) expect(parseCommand(bad), JSON.stringify(bad)).toBeNull()
})
