import { expect, test } from 'bun:test'
import type { PendingMachine } from './share.ts'
import { approveBody, CODE_PROBLEM, draftFor, draftProblem, NAME_PROBLEM, SHARE_PROBLEM, SHARE_TOO_HIGH_PROBLEM } from './shareDraft.ts'

const machine: PendingMachine = { id: 'p1', hostname: 'Far Mac', os: 'mac', cpu: 'arm64', share: { cores: 4, ram_mb: 8192, disk_gb: 100 }, expiresAt: '2026-10-31T10:15:00Z', triesLeft: 5 }

test('the draft starts with the safe host name and what the machine asked to share', () => {
  expect(draftFor(machine)).toEqual({ code: '', name: 'far-mac', cores: '4', ram_mb: '8192', disk_gb: '100' })
})

test('a draft needs a six-digit code, a safe name and a share that is not raised', () => {
  const ok = { ...draftFor(machine), code: '123456' }
  expect(draftProblem(ok, machine.share)).toBeNull()
  expect(draftProblem({ ...ok, code: '' }, machine.share)).toBe(CODE_PROBLEM)
  expect(draftProblem({ ...ok, code: '12345' }, machine.share)).toBe(CODE_PROBLEM)
  expect(draftProblem({ ...ok, code: '12a456' }, machine.share)).toBe(CODE_PROBLEM)
  expect(draftProblem({ ...ok, name: 'bad name' }, machine.share)).toBe(NAME_PROBLEM)
  expect(draftProblem({ ...ok, name: '' }, machine.share)).toBe(NAME_PROBLEM)
  expect(draftProblem({ ...ok, cores: '0' }, machine.share)).toBe(SHARE_PROBLEM)
  expect(draftProblem({ ...ok, ram_mb: '1.5' }, machine.share)).toBe(SHARE_PROBLEM)
  expect(draftProblem({ ...ok, disk_gb: '' }, machine.share)).toBe(SHARE_PROBLEM)
  expect(draftProblem({ ...ok, cores: '5' }, machine.share)).toBe(SHARE_TOO_HIGH_PROBLEM)
  expect(draftProblem({ ...ok, cores: '2', ram_mb: '1024' }, machine.share)).toBeNull()
})

test('the approve body carries trimmed text and whole numbers', () => {
  expect(approveBody({ code: ' 123456 ', name: ' my-mac ', cores: '2', ram_mb: '4096', disk_gb: '50' })).toEqual({ code: '123456', name: 'my-mac', share: { cores: 2, ram_mb: 4096, disk_gb: 50 } })
})
