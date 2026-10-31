import { expect, test } from 'bun:test'
import { parseActivity } from './mcpActivity.ts'
import { UnreadableAnswer } from './unreadable.ts'

test('activity rows lose the mcp: and mcp. prefixes and name the person', () => {
  const row = parseActivity({ activity: [{ at: '2026-10-31T10:00:00Z', actor: 'mcp:Ayu', action: 'mcp.create_vm', target: 'rtx-pc/box', status: 'ok' }] })[0]
  expect(row).toMatchObject({ person: 'Ayu', tool: 'create_vm', target: 'rtx-pc/box', status: 'ok' })
  expect(parseActivity([{ created_at: 1800000000, actor: 'mcp:a', action: 'mcp.list_vms', status: 'ok' }])[0]?.target).toBeNull()
})

test('activity that is not from an AI client or is malformed is unreadable', () => {
  for (const bad of [null, [{ at: 'x', actor: 'mcp:a', action: 'mcp.x', status: 'ok' }], [{ at: '2026-10-31T10:00:00Z', actor: 'kurnia', action: 'x', status: 'ok' }], [{ at: '2026-10-31T10:00:00Z', actor: 'mcp:a', action: 'mcp.x' }]]) {
    expect(() => parseActivity(bad)).toThrow(UnreadableAnswer)
  }
})
