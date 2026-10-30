import { expect, test } from 'bun:test'
import type { RequestParams } from './mcpRequests.ts'
import { stateWords, wantsText } from './mcpRequestText.ts'

const params = (more: Partial<RequestParams> = {}): RequestParams => ({ machine: null, vm: null, size: null, vcpu: null, ramMb: null, diskGb: null, gpuMemoryGb: null, ...more })

test('a create with a GPU limit', () => {
  expect(wantsText({ kind: 'create', params: params({ machine: 'rtx-pc', size: 'medium', gpuMemoryGb: 4 }) })).toBe('create a medium VM on rtx-pc with a 4 GB GPU limit')
})

test('a create without a machine goes to the least loaded one, with a name', () => {
  expect(wantsText({ kind: 'create', params: params({ size: 'large', vm: 'build' }) })).toBe('create a large VM called build on the least loaded machine that fits')
})

test('a custom create lists its numbers', () => {
  expect(wantsText({ kind: 'create', params: params({ machine: 'm', size: 'custom', vcpu: 12, ramMb: 32768, diskGb: 300 }) })).toBe('create a custom VM (12 vCPU, 32 GB RAM, 300 GB disk) on m')
  expect(wantsText({ kind: 'create', params: params({ machine: 'm', size: 'custom' }) })).toBe('create a custom VM (size not given) on m')
})

test('delete, start and stop name the VM and the machine', () => {
  const p = params({ machine: 'rtx-pc', vm: 'box' })
  expect(wantsText({ kind: 'delete', params: p })).toBe('delete VM box on rtx-pc')
  expect(wantsText({ kind: 'start', params: p })).toBe('start VM box on rtx-pc')
  expect(wantsText({ kind: 'stop', params: p })).toBe('stop VM box on rtx-pc')
})

test('every state has words', () => {
  expect(stateWords('denied')).toBe('denied')
  expect(stateWords('expired')).toContain('nobody')
  expect(stateWords('done')).toContain('approved')
})
