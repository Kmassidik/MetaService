import { expect, test } from 'bun:test'
import { deleteFailure, hasDeleteInProgress, withDeleting } from './deleteOrders.ts'
import { command, machine, workload } from './testing.ts'

const running = workload({ id: 'w1', state: 'running' })
const other = workload({ id: 'w2', state: 'stopped' })
const box = machine({ id: 'm', workloads: [running, other] })
const removal = (extra: Parameters<typeof command>[0] = {}) => command({ id: 'd1', type: 'delete', machine: 'm', workload_id: 'w1', state: 'queued', created_at: '2026-01-01T00:00:00Z', ...extra })

test('accepted queued and running deletes immediately mark only their own VM as deleting', () => {
  for (const state of ['queued', 'running']) {
    const shown = withDeleting([box], [removal({ state })])
    expect(shown[0]?.workloads.map((entry) => entry.state)).toEqual(['deleting', 'stopped'])
    expect(box.workloads[0]?.state).toBe('running')
    expect(shown[0]?.workloads[1]).toBe(other)
  }
})

test('another machine, another action, and a finished delete do not invent a deleting state', () => {
  const orders = [
    removal({ id: 'other-machine', machine: 'elsewhere' }),
    removal({ id: 'start', type: 'start' }),
    removal({ id: 'done', state: 'succeeded' }),
    removal({ id: 'failed', state: 'failed' }),
  ]
  const machines = [box]
  expect(withDeleting(machines, orders)).toBe(machines)
  expect(withDeleting(machines, [removal()])).not.toBe(machines)
})

test('fast polling continues for accepted orders and machine-reported deleting, then stops', () => {
  expect(hasDeleteInProgress([box], [removal()])).toBe(true)
  expect(hasDeleteInProgress([box], [removal({ state: 'running' })])).toBe(true)
  expect(hasDeleteInProgress([machine({ workloads: [workload({ state: 'deleting' })] })], [])).toBe(true)
  expect(hasDeleteInProgress([box], [removal({ state: 'succeeded' })])).toBe(false)
  expect(hasDeleteInProgress([box], [removal({ state: 'failed' })])).toBe(false)
})

test('a failed delete shows its real cleaned helper reason', () => {
  const failed = removal({ state: 'failed', result: { error: 'backup failed: disk is full' } })
  expect(deleteFailure([failed], 'm', 'w1')).toBe('backup failed: disk is full')
  expect(deleteFailure([failed], 'm', 'w2')).toBeNull()
  expect(deleteFailure([removal({ state: 'failed' })], 'm', 'w1')).toBe('The VM could not be deleted.')
})

test('only the newest delete attempt controls the visible failure', () => {
  const oldFailure = removal({ id: 'old', state: 'failed', created_at: '2026-01-01T00:00:00Z', result: { error: 'old failure' } })
  const retry = removal({ id: 'retry', state: 'running', created_at: '2026-01-01T00:01:00Z' })
  const succeeded = removal({ id: 'done', state: 'succeeded', created_at: '2026-01-01T00:02:00Z' })
  expect(deleteFailure([oldFailure, retry], 'm', 'w1')).toBeNull()
  expect(deleteFailure([oldFailure, succeeded], 'm', 'w1')).toBeNull()
  expect(deleteFailure([retry, oldFailure], 'm', 'w1')).toBeNull()
})
