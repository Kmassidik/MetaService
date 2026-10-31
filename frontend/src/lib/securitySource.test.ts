import { afterEach, expect, test } from 'bun:test'
import { eventsPath, getSecurityEvents, getSecurityOverview, overviewPath } from './securityApi.ts'
import { loadSource } from './securitySource.ts'
import { ApiError } from './api.ts'
import type { EventQuery } from './securityTypes.ts'

const NOW = Date.parse('2026-11-01T12:00:00Z')
const realFetch = globalThis.fetch
const asked: string[] = []

function answerWith(status: number, body: unknown) {
  asked.length = 0
  globalThis.fetch = Object.assign(async (input: RequestInfo | URL) => {
    asked.push(String(input))
    return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
  }, { preconnect: realFetch.preconnect })
}

afterEach(() => { globalThis.fetch = realFetch })

const query = (extra: Partial<EventQuery> = {}): EventQuery => ({ range: '7d', machine: '', type: '', q: '', cursor: null, ...extra })

test('the addresses carry the range and only the filters that are set', () => {
  expect(overviewPath('30d')).toBe('/api/security/overview?range=30d')
  expect(eventsPath(query())).toBe('/api/security/events?range=7d')
  expect(eventsPath(query({ machine: 'rtx-pc', type: 'blocked', q: ' 45.1 ', cursor: '50' }))).toBe('/api/security/events?range=7d&machine=rtx-pc&type=blocked&q=45.1&cursor=50')
})

test('a 404 from the parent means it has no security API: null, not an error', async () => {
  answerWith(404, { error: { code: 'not_found', message: 'no such route' } })
  expect(await getSecurityOverview('7d')).toBeNull()
  expect(await getSecurityEvents(query())).toBeNull()
  expect(asked).toEqual(['/api/security/overview?range=7d', '/api/security/events?range=7d'])
})

test('any other refusal is passed on, not hidden', async () => {
  answerWith(500, { error: { code: 'boom', message: 'broken' } })
  await expect(getSecurityOverview('7d')).rejects.toBeInstanceOf(ApiError)
})

test('the real source asks the parent and reads what it sends', async () => {
  answerWith(200, { range: '7d', machines: [{ machine: 'a', reported: true, last_reported: '2026-11-01T11:00:00Z', failed: 5, blocked: 1 }] })
  const { source, machines } = await loadSource(false, NOW)
  expect(machines).toBeNull()
  expect((await source.overview('7d'))?.machines[0]?.failed).toBe(5)
  expect(asked).toEqual(['/api/security/overview?range=7d'])
})

test('the real source never answers with the sample, even when the parent has nothing', async () => {
  answerWith(404, {})
  const { source } = await loadSource(false, NOW)
  expect(await source.overview('90d')).toBeNull()
  expect(await source.events(query({ range: '90d' }))).toBeNull()
})

test('the preview answers from the sample and never asks the parent', async () => {
  answerWith(500, {})
  const { source, machines } = await loadSource(true, NOW)
  expect(machines?.map((machine) => machine.name)).toEqual(['Mac Studio', 'Mac Mini', 'DGX Spark', 'RTX 5090 PC'])
  const overview = await source.overview('30d')
  expect(overview?.machines.map((line) => line.machine)).toEqual(['mac-studio', 'dgx-spark', 'rtx-5090-pc'])
  expect(asked).toEqual([])
})

test('the sample is modelled on the real machines', async () => {
  const { source } = await loadSource(true, NOW)
  const overview = await source.overview('30d')
  const failed = (id: string) => overview?.machines.find((line) => line.machine === id)?.failed ?? 0
  expect(failed('rtx-5090-pc')).toBeGreaterThan(90_000)
  expect(failed('rtx-5090-pc')).toBeLessThan(102_000)
  expect(failed('dgx-spark')).toBeGreaterThan(31_000)
  expect(failed('dgx-spark')).toBeLessThan(35_000)
  expect(overview?.machines.find((line) => line.machine === 'dgx-spark')?.baseline.password_login).toBe(true)
  const users = overview?.top_users.map((row) => row.name) ?? []
  expect(users[0]).toBe('ubuntu')
  for (const name of ['ubuntu', 'user', 'test', 'admin', 'postgres']) expect(users).toContain(name)
  const events = await source.events(query({ range: '30d', machine: 'rtx-5090-pc', type: 'failed_login' }))
  expect(new Set((await collect(source, 'rtx-5090-pc')).map((event) => event.address)).size).toBe(24)
  expect(events?.events).toHaveLength(50)
  expect(events?.next_cursor).not.toBeNull()
})

async function collect(source: Awaited<ReturnType<typeof loadSource>>['source'], machine: string) {
  const all = []
  let cursor: string | null = null
  do {
    const page = await source.events(query({ range: '30d', machine, type: 'failed_login', cursor }))
    all.push(...(page?.events ?? []))
    cursor = page?.next_cursor ?? null
  } while (cursor !== null)
  return all
}
