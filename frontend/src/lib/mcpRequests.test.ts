import { expect, test } from 'bun:test'
import { parseActivity, parseApprovals } from './mcpRequests.ts'
import { UnreadableAnswer } from './unreadable.ts'

const ask = (more: Record<string, unknown> = {}) => ({
  id: 'r1', token_name: 'laptop', kind: 'create', params: { machine: 'rtx-pc', size: 'medium', gpu_memory_gb: 4 }, state: 'pending_approval',
  created_at: '2026-10-31T10:00:00Z', expires_at: '2026-11-01T10:00:00Z', decided_by: null, decided_at: null, ...more,
})

test('approvals come as {pending, recent}', () => {
  const read = parseApprovals({ pending: [ask()], recent: [ask({ id: 'r2', state: 'denied', decided_by: 'kurnia', decided_at: '2026-10-31T11:00:00Z' })] })
  expect(read.pending[0]?.params.gpuMemoryGb).toBe(4)
  expect(read.pending[0]?.params.machine).toBe('rtx-pc')
  expect(read.recent[0]?.decidedBy).toBe('kurnia')
})

test('one bare list is split by state', () => {
  const read = parseApprovals([ask(), ask({ id: 'r3', state: 'done' })])
  expect(read.pending.map((row) => row.id)).toEqual(['r1'])
  expect(read.recent.map((row) => row.id)).toEqual(['r3'])
})

test('a name next to an id wins for the machine and the VM', () => {
  const read = parseApprovals({ pending: [ask({ kind: 'delete', params: { machine: 'm-1', machine_name: 'rtx-pc', vm: 'w-9', vm_name: 'build-box' } })] })
  expect(read.pending[0]?.params.machine).toBe('rtx-pc')
  expect(read.pending[0]?.params.vm).toBe('build-box')
})

test('an unknown kind, state or a wrongly typed number is unreadable', () => {
  for (const bad of [null, {}, { pending: [ask({ kind: 'format' })] }, { pending: [ask({ state: 'maybe' })] }, { pending: [ask({ params: { vcpu: 'two' } })] }, { pending: [ask({ token_name: 5 })] }]) {
    expect(() => parseApprovals(bad)).toThrow(UnreadableAnswer)
  }
})

test('activity rows lose the mcp: and mcp. prefixes', () => {
  const row = parseActivity({ activity: [{ at: '2026-10-31T10:00:00Z', actor: 'mcp:laptop', action: 'mcp.create_vm', target: 'rtx-pc/box', status: 'ok' }] })[0]
  expect(row).toMatchObject({ tokenName: 'laptop', tool: 'create_vm', target: 'rtx-pc/box', status: 'ok' })
  expect(parseActivity([{ created_at: 1800000000, actor: 'mcp:a', action: 'mcp.list_vms', status: 'ok' }])[0]?.target).toBeNull()
})

test('activity that is not from an AI client or is malformed is unreadable', () => {
  for (const bad of [null, [{ at: 'x', actor: 'mcp:a', action: 'mcp.x', status: 'ok' }], [{ at: '2026-10-31T10:00:00Z', actor: 'kurnia', action: 'x', status: 'ok' }], [{ at: '2026-10-31T10:00:00Z', actor: 'mcp:a', action: 'mcp.x' }]]) {
    expect(() => parseActivity(bad)).toThrow(UnreadableAnswer)
  }
})
