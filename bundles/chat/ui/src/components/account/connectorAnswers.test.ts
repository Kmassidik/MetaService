import { expect, test } from 'bun:test'
import { parseApprovalAnswer, parseApprovalList, parseConnectorAnswer, parseExecuteResult, parseTools } from './connectorAnswers.ts'

const approval = {
  id: 'a1', state: 'pending', tool: 'send', argsJSON: '{"to":"x"}', actionHash: 'h1', connectorId: 'c1', expiresAt: '2030-01-01T00:00:00Z',
}

test('parseApprovalList returns a valid approval list', () => {
  expect(parseApprovalList({ approvals: [approval] })).toEqual([approval])
})

test('parseApprovalList accepts an empty list', () => {
  expect(parseApprovalList({ approvals: [] })).toEqual([])
})

test('parseApprovalList rejects an approval with a missing field', () => {
  const { actionHash: _omitted, ...incomplete } = approval
  expect(() => parseApprovalList({ approvals: [incomplete] })).toThrow('approval list')
})

test('parseApprovalList rejects a field of the wrong type', () => {
  expect(() => parseApprovalList({ approvals: [{ ...approval, expiresAt: 12 }] })).toThrow('approval list')
})

test('parseApprovalList rejects a missing list and non-object answers', () => {
  expect(() => parseApprovalList({})).toThrow('approval list')
  expect(() => parseApprovalList(null)).toThrow('approval list')
  expect(() => parseApprovalList('approvals')).toThrow('approval list')
})

test('hostile strings pass through as plain text and never run', () => {
  const hostile = { ...approval, tool: '<img src=x onerror=alert(1)>', argsJSON: '__proto__', id: "'; DROP TABLE" }
  expect(parseApprovalAnswer({ approval: hostile })).toEqual(hostile)
})

test('parseApprovalAnswer rejects an answer without an approval', () => {
  expect(() => parseApprovalAnswer({ approval: null })).toThrow('approval')
})

test('parseConnectorAnswer keeps the optional revoked flag and rejects a wrong type', () => {
  expect(parseConnectorAnswer({ connector: { id: 'c1', name: 'Mail', revoked: true } }).revoked).toBe(true)
  expect(() => parseConnectorAnswer({ connector: { id: 'c1', name: 'Mail', revoked: 'yes' } })).toThrow('connector')
})

test('parseTools defaults to an empty list and checks each tool', () => {
  expect(parseTools({})).toEqual([])
  expect(parseTools({ tools: [{ name: 'send', description: 'Send mail' }] })).toHaveLength(1)
  expect(() => parseTools({ tools: [{ description: 'no name' }] })).toThrow('tool list')
})

test('parseExecuteResult returns any result and allows none', () => {
  expect(parseExecuteResult({ result: { ok: true } })).toEqual({ ok: true })
  expect(parseExecuteResult({})).toBeUndefined()
})
