import { expect, test } from 'bun:test'
import { BACKFILLED_NOTE, BEFORE_TRACKING, createdByText, originLabel, originRows, parseOrigin, readCreatedBy, UNKNOWN_ORIGIN, workloadCreatedByText } from './vmOrigin.ts'
import { UnreadableAnswer } from './unreadable.ts'

const record = (more: Record<string, unknown> = {}) => ({
  kind: 'mcp', actor: 'mcp:Ayu', person_name: 'Ayu', token_prefix: 'AbCd1234', client: 'claude-code 2.1.0', source_ip: '203.0.113.7',
  created_at: '2026-10-31T12:00:00Z', deleted_at: null, deleted_by: null, fingerprint: '7f3a9c21', intact: true, ...more,
})

test('the short creator reads as "label · fingerprint", or as unknown origin', () => {
  expect(createdByText(readCreatedBy({ kind: 'mcp', label: 'Ayu (MCP)', fingerprint: '7f3a9c21' }))).toBe('Ayu (MCP) · 7f3a9c21')
  expect(createdByText(readCreatedBy({ kind: 'panel', label: 'panel (kurnia)', fingerprint: '5b02d1ee' }))).toBe('panel (kurnia) · 5b02d1ee')
  expect(createdByText(null)).toBe(UNKNOWN_ORIGIN)
  expect(workloadCreatedByText({})).toBe(UNKNOWN_ORIGIN)
  expect(workloadCreatedByText({ created_by: null })).toBe(UNKNOWN_ORIGIN)
})

test('a value in another shape is no creator, never a broken list', () => {
  for (const odd of [undefined, 'Ayu', [], { kind: 'robot', label: 'x', fingerprint: 'y' }, { kind: 'mcp', label: '', fingerprint: 'y' }, { kind: 'mcp', label: 'x' }, { kind: 'mcp', label: 3, fingerprint: 'y' }]) {
    expect(readCreatedBy(odd)).toBeNull()
  }
})

test('the full record is read strictly', () => {
  const read = parseOrigin({ origin: record() })
  expect(read?.fingerprint).toBe('7f3a9c21')
  expect(read?.intact).toBe(true)
  expect(read?.createdAt).toBe(Date.parse('2026-10-31T12:00:00Z'))
  expect(read?.backfilled).toBe(false)
  expect(parseOrigin({ origin: null })).toBeNull()
  for (const bad of [null, [], { origin: 'x' }, { origin: record({ intact: 'yes' }) }, { origin: record({ kind: 'x' }) }, { origin: record({ fingerprint: 1 }) }, { origin: record({ created_at: 'soon' }) }, { origin: record({ created_at: 5, actor: undefined }) }]) {
    expect(() => parseOrigin(bad)).toThrow(UnreadableAnswer)
  }
})

test('labels for both doors', () => {
  expect(originLabel({ kind: 'mcp', actor: 'mcp:Ayu', personName: 'Ayu', backfilled: false })).toBe('Ayu (MCP)')
  expect(originLabel({ kind: 'mcp', actor: 'Ayu', personName: null, backfilled: false })).toBe('Ayu (MCP)')
  expect(originLabel({ kind: 'panel', actor: 'kurnia', personName: null, backfilled: false })).toBe('panel (kurnia)')
})

test('the VM page rows list what the record has, with the time in UTC', () => {
  const rows = originRows(parseOrigin({ origin: record() })!)
  expect(rows.map((row) => `${row.label}: ${row.value}`)).toEqual([
    'Created by: Ayu (MCP) · 7f3a9c21', 'Client: claude-code 2.1.0', 'Token: msk_AbCd1234…', 'From: 203.0.113.7', 'Created: 2026-10-31 12:00 UTC',
  ])
  const panel = originRows(parseOrigin({ origin: record({ kind: 'panel', actor: 'kurnia', person_name: null, token_prefix: null, client: null, source_ip: null, deleted_at: '2026-11-01T08:30:00Z', deleted_by: 'kurnia' }) })!)
  expect(panel.map((row) => row.label)).toEqual(['Created by', 'Created', 'Deleted'])
  expect(panel[2]?.value).toBe('2026-11-01 08:30 UTC by kurnia')
})

test('a VM made before tracking: no date, a note, and the label says it was recorded afterwards', () => {
  const old = parseOrigin({ origin: record({ kind: 'panel', actor: 'admin', person_name: null, token_prefix: null, client: null, source_ip: null, created_at: null, backfilled: true }) })!
  expect(old.createdAt).toBeNull()
  expect(old.backfilled).toBe(true)
  expect(originLabel(old)).toBe('admin (recorded afterwards)')
  expect(originRows(old).map((row) => `${row.label}: ${row.value}`)).toEqual(['Created by: admin (recorded afterwards) · 7f3a9c21', `Created: ${BEFORE_TRACKING}`])
  expect(createdByText(readCreatedBy({ kind: 'panel', label: 'admin (recorded afterwards)', fingerprint: '0a1b2c3d' }))).toBe('admin (recorded afterwards) · 0a1b2c3d')
  expect(BACKFILLED_NOTE).toContain('before creators were tracked')
})
