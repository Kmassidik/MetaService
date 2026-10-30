import { afterEach, beforeEach, expect, test } from 'bun:test'
import { ApiError, shareApprove, shareMakeCommand, shareRemovePeer, shareSupported } from './api.ts'
import { UnreadableAnswer } from './unreadable.ts'

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

test('a wrong code is shown with its tries left and is sent only once (no CSRF retry)', async () => {
  replies = [{ status: 403, body: { error: 'wrong_code', tries_left: 2 } }]
  const error = await failure(shareApprove('p1', { code: '000000', name: 'a', share: { cores: 1, ram_mb: 1, disk_gb: 1 } }))
  expect(error.code).toBe('wrong_code')
  expect(error.message).toBe('That code is wrong. 2 tries left.')
  expect(calls.length).toBe(1)
  expect(calls[0]?.path).toBe('/api/join-share/pending/p1/approve')
})

test('the parent own 403 (CSRF) is still retried once, as for every other write', async () => {
  replies = [{ status: 403, body: { error: { code: 'forbidden', message: 'missing or wrong CSRF token' } } }, { status: 200, body: { username: 'k', csrf_token: 't' } }, { status: 200, body: { address: '10.77.0.2' } }]
  await shareApprove('p1', { code: '123456', name: 'a', share: { cores: 1, ram_mb: 1, disk_gb: 1 } })
  expect(calls.map((call) => call.path)).toEqual(['/api/join-share/pending/p1/approve', '/api/session', '/api/join-share/pending/p1/approve'])
})

test('not set up and hub not answering come with their plain sentences and codes', async () => {
  replies = [{ status: 404, body: { error: 'not_configured' } }, { status: 502, body: { error: 'hub_unreachable' } }]
  const first = await failure(shareSupported())
  expect([first.status, first.code, first.message]).toEqual([404, 'not_configured', 'Share a PC is not set up on this parent.'])
  const second = await failure(shareSupported())
  expect([second.status, second.code]).toEqual([502, 'hub_unreachable'])
})

test('a name already used is a plain message', async () => {
  replies = [{ status: 409, body: { error: 'name_taken' } }]
  expect((await failure(shareApprove('p1', { code: '123456', name: 'a', share: { cores: 1, ram_mb: 1, disk_gb: 1 } }))).message).toBe('That name is already used. Choose another name.')
})

test('the command call sends the system and CPU, and an unreadable answer is not trusted', async () => {
  replies = [{ status: 200, body: { nope: true } }]
  await shareMakeCommand('mac', 'arm64').then(() => { throw new Error('should fail') }, (error: unknown) => expect(error).toBeInstanceOf(UnreadableAnswer))
  expect(calls[0]?.method).toBe('POST')
  expect(JSON.parse(calls[0]?.body ?? '')).toEqual({ os: 'mac', cpu: 'arm64' })
})

test('a name in a path is encoded', async () => {
  await shareRemovePeer('a b/c')
  expect(calls[0]).toMatchObject({ method: 'DELETE', path: '/api/join-share/peers/a%20b%2Fc' })
})
