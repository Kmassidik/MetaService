import { afterEach, beforeEach, expect, jest, test } from 'bun:test'
import { ApiError, TIMEOUT_CODE, remoteFix, remoteProbe, remoteRemove, remoteVerify, updateHelper, workloadAction } from './api.ts'
import { LONG_REQUEST_TIMEOUT_MS, REQUEST_TIMEOUT_MS, TIMEOUT_MESSAGE } from './timeouts.ts'

const realFetch = globalThis.fetch
let signals: AbortSignal[] = []

const asFetch = (handler: (init?: RequestInit) => Promise<Response>): typeof fetch => Object.assign((_path: unknown, init?: RequestInit) => handler(init), { preconnect: () => {} })

/** A fetch that never answers; it only fails when its request is cancelled. */
const silentFetch = asFetch((init) => {
  const signal = init?.signal
  if (signal) signals.push(signal)
  return new Promise((_resolve, reject) => {
    signal?.addEventListener('abort', () => reject(new DOMException('cancelled', 'AbortError')))
  })
})

beforeEach(() => {
  signals = []
  jest.useFakeTimers()
  globalThis.fetch = silentFetch
})

afterEach(() => {
  jest.useRealTimers()
  globalThis.fetch = realFetch
})

async function failureOf(request: Promise<unknown>): Promise<ApiError> {
  const error = await request.then(() => null, (reason: unknown) => reason)
  if (!(error instanceof ApiError)) throw new Error('expected an ApiError')
  return error
}

test('a request that gets no answer fails with the plain timeout message', async () => {
  const request = failureOf(workloadAction('mac', 'vm1', 'start'))
  jest.advanceTimersByTime(REQUEST_TIMEOUT_MS - 1)
  expect(signals[0]?.aborted).toBe(false)
  jest.advanceTimersByTime(1)
  const error = await request
  expect(error.code).toBe(TIMEOUT_CODE)
  expect(error.message).toBe(TIMEOUT_MESSAGE)
  expect(signals[0]?.aborted).toBe(true)
})

test('the SSH routes wait five minutes, not thirty seconds', async () => {
  const routes = [
    () => remoteProbe({ host: 'x' }),
    () => remoteVerify({}),
    () => remoteFix({}),
    () => remoteRemove('m', {}),
    () => updateHelper('m'),
  ]
  const requests = routes.map((route) => failureOf(route()))
  jest.advanceTimersByTime(REQUEST_TIMEOUT_MS)
  expect(signals).toHaveLength(routes.length)
  expect(signals.some((signal) => signal.aborted)).toBe(false)
  jest.advanceTimersByTime(LONG_REQUEST_TIMEOUT_MS - REQUEST_TIMEOUT_MS)
  expect(signals.every((signal) => signal.aborted)).toBe(true)
  for (const error of await Promise.all(requests)) expect(error.code).toBe(TIMEOUT_CODE)
})

test('an answer in time is not cut off later', async () => {
  globalThis.fetch = asFetch(async (init) => {
    if (init?.signal) signals.push(init.signal)
    return new Response('{}', { status: 200 })
  })
  await workloadAction('mac', 'vm1', 'stop')
  jest.advanceTimersByTime(LONG_REQUEST_TIMEOUT_MS)
  expect(signals[0]?.aborted).toBe(false)
})

test('a refusal keeps its own message, not the timeout one', async () => {
  globalThis.fetch = asFetch(async () => new Response(JSON.stringify({ error: { code: 'no_room', message: 'No room' } }), { status: 409 }))
  const error = await failureOf(workloadAction('mac', 'vm1', 'start'))
  expect(error.code).toBe('no_room')
})

test('a network failure is still "cannot reach"', async () => {
  globalThis.fetch = asFetch(async () => { throw new TypeError('offline') })
  const error = await failureOf(workloadAction('mac', 'vm1', 'start'))
  expect(error.code).toBe('unreachable')
})
