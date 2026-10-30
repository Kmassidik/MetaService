import { expect, test } from 'bun:test'
import { draftFor, draftProblem, toggleScope, tokenBody } from './mcpDraft.ts'

test('the starting values are the spec defaults with auto-approve off', () => {
  const draft = draftFor()
  expect(draft).toMatchObject({ name: '', scopes: ['read', 'create'], maxVms: 3, maxVcpu: 8, maxRamGb: 16, maxDiskGb: 200, createsPerDay: 10, gpuMemoryGb: 8, expiresInDays: 90, autoApprove: false })
})

test('the body sends RAM in MB and leaves the GPU cap out without the gpu scope', () => {
  const body = tokenBody({ ...draftFor(), name: '  laptop ' })
  expect(body).toEqual({
    name: 'laptop', scopes: ['read', 'create'],
    quotas: { max_vms: 3, max_vcpu: 8, max_ram_mb: 16384, max_disk_gb: 200, creates_per_day: 10 },
    expires_in_days: 90, auto_approve: false,
  })
})

test('the gpu scope adds the cap and the scopes keep the spec order', () => {
  const body = tokenBody({ ...draftFor(), name: 'a', scopes: toggleScope(['create', 'read'], 'gpu', true) })
  expect(body.scopes).toEqual(['read', 'create', 'gpu'])
  expect(body.quotas.gpu_memory_gb).toBe(8)
})

test('toggling a scope', () => {
  expect(toggleScope(['read'], 'create', true)).toEqual(['read', 'create'])
  expect(toggleScope(['read', 'create'], 'read', false)).toEqual(['create'])
  expect(toggleScope(['read'], 'read', true)).toEqual(['read'])
})

test('what is wrong with a draft is said in plain words', () => {
  const ok = { ...draftFor(), name: 'laptop' }
  expect(draftProblem(ok)).toBeNull()
  expect(draftProblem({ ...ok, name: '   ' })).toContain('name')
  expect(draftProblem({ ...ok, name: 'x'.repeat(65) })).toContain('64')
  expect(draftProblem({ ...ok, scopes: [] })).toContain('at least one')
  expect(draftProblem({ ...ok, maxVms: 0 })).toContain('whole numbers')
  expect(draftProblem({ ...ok, maxVcpu: null })).toContain('whole numbers')
  expect(draftProblem({ ...ok, createsPerDay: 1.5 })).toContain('whole numbers')
  expect(draftProblem({ ...ok, expiresInDays: 366 })).toContain('365')
  expect(draftProblem({ ...ok, expiresInDays: null })).toContain('days')
  expect(draftProblem({ ...ok, scopes: ['gpu'], gpuMemoryGb: null })).toContain('whole numbers')
  expect(draftProblem({ ...ok, gpuMemoryGb: null })).toBeNull()
})
