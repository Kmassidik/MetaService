import { afterEach, beforeEach, expect, test } from 'bun:test'
import { ApiError, mcpActivity, mcpAddPerson, mcpCreateToken, mcpDisablePerson, mcpEditPerson, mcpEnablePerson, mcpInfo, mcpPeople, mcpRevokeToken, mcpTokens, workloadOrigin } from './api.ts'
import { personBody, personDraftFor, personPatch, tokenBody } from './mcpDraft.ts'

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

test('the reads use the spec routes', async () => {
  replies = [{ status: 200, body: { endpoint: 'x' } }, { status: 200, body: { people: [] } }, { status: 200, body: { tokens: [] } }, { status: 200, body: { activity: [] } }, { status: 200, body: { origin: null } }]
  await mcpInfo()
  await mcpPeople()
  await mcpTokens()
  await mcpActivity(20)
  expect(await workloadOrigin('studio', 'vm 1')).toBeNull()
  expect(calls.map((call) => `${call.method} ${call.path}`)).toEqual(['GET /api/mcp/info', 'GET /api/mcp/people', 'GET /api/mcp/tokens', 'GET /api/mcp/activity?limit=20', 'GET /api/machines/studio/workloads/vm%201/origin'])
})

test('the writes use the spec routes and the encoded id', async () => {
  replies = [{ status: 201, body: {} }, { status: 200, body: {} }, { status: 200, body: {} }, { status: 200, body: {} }, { status: 201, body: { token: 'msk_abc' } }]
  const draft = { ...personDraftFor(), name: 'Ayu' }
  await mcpAddPerson(personBody(draft))
  await mcpEditPerson('p/1', personPatch(draft))
  await mcpDisablePerson('p 1')
  await mcpEnablePerson('p2')
  expect(await mcpCreateToken(tokenBody({ name: 'a', personId: 'p1', scopes: ['read'], expiresInDays: 30 }))).toBe('msk_abc')
  await mcpRevokeToken('t 1')
  expect(calls.map((call) => `${call.method} ${call.path}`)).toEqual([
    'POST /api/mcp/people', 'PATCH /api/mcp/people/p%2F1', 'POST /api/mcp/people/p%201/disable', 'POST /api/mcp/people/p2/enable', 'POST /api/mcp/tokens', 'DELETE /api/mcp/tokens/t%201',
  ])
  expect(JSON.parse(calls[0]?.body ?? '').name).toBe('Ayu')
  expect(JSON.parse(calls[4]?.body ?? '')).toEqual({ name: 'a', person_id: 'p1', scopes: ['read'], expires_in_days: 30 })
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
  replies = [{ status: 409, body: { error: { code: 'name_taken', message: 'There is already a person with that name.' } } }]
  expect((await failure(mcpAddPerson(personBody({ ...personDraftFor(), name: 'Ayu' })))).message).toBe('There is already a person with that name.')
})
