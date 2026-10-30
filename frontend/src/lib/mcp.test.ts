import { expect, test } from 'bun:test'
import { DEFAULT_QUOTAS, parseInfo, parseMadeToken, parseTokens } from './mcp.ts'
import { UnreadableAnswer } from './unreadable.ts'

const quotas = { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10 }
const token = (more: Record<string, unknown> = {}) => ({
  id: 't1', name: 'laptop', prefix: 'AbCd1234', scopes: ['read', 'create'], quotas, auto_approve: false,
  created_at: '2026-10-30T10:00:00Z', expires_at: '2027-01-28T10:00:00Z', last_used_at: null, revoked_at: null, ...more,
})

test('a token list is read from a bare list or from {tokens}', () => {
  expect(parseTokens([token()]).length).toBe(1)
  const read = parseTokens({ tokens: [token({ last_used_at: '2026-10-31T09:00:00Z' })] })[0]
  expect(read?.name).toBe('laptop')
  expect(read?.quotas.maxRamMb).toBe(16384)
  expect(read?.quotas.gpuMemoryGb).toBeNull()
  expect(read?.lastUsedAt).toBe(Date.parse('2026-10-31T09:00:00Z'))
})

test('a number is read as seconds since 1970', () => {
  expect(parseTokens([token({ expires_at: 1800000000 })])[0]?.expiresAt).toBe(1800000000000)
})

test('an unreadable token list throws and is never an empty list', () => {
  for (const bad of [null, 'x', {}, { tokens: 'x' }, [token({ scopes: ['root'] })], [token({ quotas: { max_vms: 0 } })], [token({ auto_approve: 'no' })], [token({ expires_at: 'soon' })], [token({ name: 7 })]]) {
    expect(() => parseTokens(bad)).toThrow(UnreadableAnswer)
  }
})

test('the new token text is read from {token}; anything else is unreadable', () => {
  expect(parseMadeToken({ token: 'msk_abc', id: 't1' })).toBe('msk_abc')
  for (const bad of [null, {}, { token: '' }, { token: { id: 1 } }]) expect(() => parseMadeToken(bad)).toThrow(UnreadableAnswer)
})

test('the info needs an endpoint; tools may be names or objects; defaults fall back to the spec', () => {
  const info = parseInfo({ endpoint: 'https://meta.example/mcp', tools: ['list_vms', { name: 'create_vm' }] })
  expect(info.tools).toEqual(['list_vms', 'create_vm'])
  expect(info.defaults.quotas).toEqual(DEFAULT_QUOTAS)
  expect(info.defaults.scopes).toEqual(['read', 'create'])
  expect(info.defaults.expiryDays).toBe(90)
  for (const bad of [null, {}, { endpoint: '' }, { endpoint: 'x', tools: [3] }, { endpoint: 'x', defaults: { scopes: ['nope'] } }]) expect(() => parseInfo(bad)).toThrow(UnreadableAnswer)
})

test('the parent defaults win when sent', () => {
  const info = parseInfo({ endpoint: 'x', defaults: { scopes: ['read'], expires_in_days: 30, quotas: { ...quotas, max_vms: 1 } } })
  expect(info.defaults.quotas.maxVms).toBe(1)
  expect(info.defaults.quotas.gpuMemoryGb).toBe(8)
  expect(info.defaults.expiryDays).toBe(30)
})
