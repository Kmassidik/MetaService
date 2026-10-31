import { expect, test } from 'bun:test'
import type { McpPerson } from './mcp.ts'
import { NAME_PROBLEM, personBody, personDraftFor, personPatch, personProblem, toggleScope, tokenBody, tokenDraftFor, tokenProblem } from './mcpDraft.ts'

const ayu: McpPerson = { id: 'p1', name: 'Ayu', scopes: ['read', 'create'], quotas: { maxVms: 2, maxVcpu: 4, maxRamMb: 8192, maxDiskGb: 100, createsPerDay: 5, gpuMemoryGb: null }, tokens: 1, vmsAlive: 0, lastUsedAt: null, disabledAt: null }

test('Add person starts with the spec defaults', () => {
  expect(personDraftFor()).toMatchObject({ name: '', scopes: ['read', 'create'], maxVms: 3, maxVcpu: 8, maxRamGb: 16, maxDiskGb: 200, createsPerDay: 10, gpuMemoryGb: 8 })
})

test('Edit person starts with the person own values', () => {
  expect(personDraftFor(undefined, ayu)).toMatchObject({ name: 'Ayu', maxVms: 2, maxRamGb: 8, maxDiskGb: 100, createsPerDay: 5 })
})

test('the person body sends RAM in MB and leaves the GPU cap out without the gpu scope', () => {
  expect(personBody({ ...personDraftFor(), name: '  Ayu ' })).toEqual({
    name: 'Ayu', scopes: ['read', 'create'], quotas: { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10 },
  })
})

test('the gpu scope adds the cap, scopes keep the spec order, and an edit has no name', () => {
  const draft = { ...personDraftFor(), name: 'a', scopes: toggleScope(['create', 'read'], 'gpu', true) }
  expect(personBody(draft).scopes).toEqual(['read', 'create', 'gpu'])
  expect(personBody(draft).quotas.gpu_memory_gb).toBe(8)
  expect(personPatch(draft)).not.toHaveProperty('name')
})

test('toggling a scope', () => {
  expect(toggleScope(['read'], 'create', true)).toEqual(['read', 'create'])
  expect(toggleScope(['read', 'create'], 'read', false)).toEqual(['create'])
  expect(toggleScope(['read'], 'read', true)).toEqual(['read'])
})

test('what is wrong with a person is said in plain words', () => {
  const ok = { ...personDraftFor(), name: 'Ayu' }
  expect(personProblem(ok, true)).toBeNull()
  expect(personProblem({ ...ok, name: '   ' }, true)).toBe(NAME_PROBLEM)
  expect(personProblem({ ...ok, name: 'x'.repeat(41) }, true)).toBe(NAME_PROBLEM)
  expect(personProblem({ ...ok, name: '<b>' }, true)).toBe(NAME_PROBLEM)
  expect(personProblem({ ...ok, name: '' }, false)).toBeNull()
  expect(personProblem({ ...ok, scopes: [] }, true)).toContain('at least one')
  expect(personProblem({ ...ok, maxVms: 0 }, true)).toContain('whole numbers')
  expect(personProblem({ ...ok, maxVcpu: null }, true)).toContain('whole numbers')
  expect(personProblem({ ...ok, createsPerDay: 1.5 }, true)).toContain('whole numbers')
  expect(personProblem({ ...ok, scopes: ['gpu'], gpuMemoryGb: null }, true)).toContain('whole numbers')
  expect(personProblem({ ...ok, gpuMemoryGb: null }, true)).toBeNull()
})

test('Create token starts with the first person who is not disabled and all their scopes', () => {
  const off: McpPerson = { ...ayu, id: 'p0', name: 'Old', disabledAt: 1 }
  expect(tokenDraftFor([off, ayu])).toEqual({ name: '', personId: 'p1', scopes: ['read', 'create'], expiresInDays: 90 })
  expect(tokenDraftFor([off]).personId).toBe('')
  expect(tokenDraftFor([], 30).expiresInDays).toBe(30)
})

test('the token body names the person and has no quotas', () => {
  const body = tokenBody({ name: ' laptop ', personId: 'p1', scopes: ['create', 'read'], expiresInDays: 30 })
  expect(body).toEqual({ name: 'laptop', person_id: 'p1', scopes: ['read', 'create'], expires_in_days: 30 })
})

test('what is wrong with a token is said in plain words', () => {
  const ok = { name: 'laptop', personId: 'p1', scopes: ['read' as const], expiresInDays: 90 }
  expect(tokenProblem(ok, ayu)).toBeNull()
  expect(tokenProblem(ok, undefined)).toContain('which person')
  expect(tokenProblem({ ...ok, name: '' }, ayu)).toBe(NAME_PROBLEM)
  expect(tokenProblem({ ...ok, scopes: [] }, ayu)).toContain('at least one')
  expect(tokenProblem({ ...ok, scopes: ['destroy'] }, ayu)).toContain('Ayu does not have')
  expect(tokenProblem({ ...ok, expiresInDays: 366 }, ayu)).toContain('365')
  expect(tokenProblem({ ...ok, expiresInDays: null }, ayu)).toContain('days')
})
