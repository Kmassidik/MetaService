import { afterEach, beforeEach, expect, test } from 'bun:test'
import { ApiError, mcpActivity, mcpApprovals, mcpApprove, mcpCreateToken, mcpDeny, mcpInfo, mcpRevokeToken, mcpTokens } from './api.ts'
import { draftFor, tokenBody } from './mcpDraft.ts'

const realFetch = globalThis.fetch
const calls: { path: string; method: string; body: string }[] = []
let replies: { status: number; body: unknown }[] = []

beforeEach(() => {
  calls.length = 0
  replies = []
  globalThis.fetch = Object.assign(async (path: unknown, init?: RequestInit) => {
    calls.push({ path: String(path), method: init?.method ?? 'GET', body: String(init?.body ?? '') })
    const reply = replies.shift() ?? { status: 200, body: {} }
    return new Response(JSON.stringify(reply.body), { status: reply.status, headers: { 'Content-Type': 'application/json' } })
  }, { preconnect: () => {} }) as typeof fetch
})

afterEach(() => {
  globalThis.fetch = realFetch
})

const failure = async (work: Promise<unknown>): Promise<ApiError> => {
  const error = await work.then(() => null, (reason: unknown) => reason)
  if (!(error instanceof ApiError)) throw new Error('expected an ApiError')
  return error
}

test('the routes are the ones in the spec', async () => {
  replies = [{ status: 200, body: { endpoint: 'x' } }, { status: 200, body: { tokens: [] } }, { status: 200, body: { pending: [] } }, { status: 200, body: { activity: [] } }]
  await mcpInfo()
  await mcpTokens()
  await mcpApprovals()
  await mcpActivity(20)
  expect(calls.map((call) => `${call.method} ${call.path}`)).toEqual(['GET /api/mcp/info', 'GET /api/mcp/tokens', 'GET /api/mcp/approvals', 'GET /api/mcp/activity?limit=20'])
})

test('the writes use the spec routes and the encoded id', async () => {
  replies = [{ status: 200, body: { token: 'msk_abc' } }]
  expect(await mcpCreateToken(tokenBody({ ...draftFor(), name: 'a' }))).toBe('msk_abc')
  await mcpRevokeToken('t 1')
  await mcpApprove('r/1')
  await mcpDeny('r2')
  expect(calls.map((call) => `${call.method} ${call.path}`)).toEqual(['POST /api/mcp/tokens', 'DELETE /api/mcp/tokens/t%201', 'POST /api/mcp/approvals/r%2F1/approve', 'POST /api/mcp/approvals/r2/deny'])
  expect(JSON.parse(calls[0]?.body ?? '').name).toBe('a')
})

test('a parent that is too old answers 404, which the section reads from the status', async () => {
  replies = [{ status: 404, body: { error: { code: 'not_found', message: '/api/mcp/info' } } }]
  expect((await failure(mcpInfo())).status).toBe(404)
})

test('an answer in another shape is a bad_reply, never an empty list', async () => {
  replies = [{ status: 200, body: { tokens: 'x' } }]
  const error = await failure(mcpTokens())
  expect(error.code).toBe('bad_reply')
})

test('a refusal keeps the parent plain reason', async () => {
  replies = [{ status: 409, body: { error: { code: 'not_pending', message: 'This request was already decided.' } } }]
  expect((await failure(mcpApprove('r1'))).message).toBe('This request was already decided.')
})
