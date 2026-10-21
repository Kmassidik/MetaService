import { test, expect } from 'bun:test'
import { evidence, headline, parseGpuCheck, type GpuCheckAnswer } from './gpuCheck.ts'

const smi: GpuCheckAnswer = { gpu_visible: true, how: 'nvidia-smi', detail: 'NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB', note: 'The GPU is visible inside, and nvidia-smi can talk to it.' }

test('an answer in the promised shape is read', () => {
  expect(parseGpuCheck(smi)).toEqual(smi)
  expect(parseGpuCheck({ ...smi, how: 'device nodes', detail: '' })?.how).toBe('device nodes')
})

test('anything else is refused', () => {
  for (const bad of [null, 'yes', [], {}, { ...smi, how: 'magic' }, { ...smi, gpu_visible: 'true' }, { ...smi, detail: 5 }, { ...smi, note: null }, { ...smi, extra: 1 }]) {
    expect(parseGpuCheck(bad)).toBeNull()
  }
})

test('the headline and the evidence say what was found and how', () => {
  const found = parseGpuCheck(smi)
  expect(found && headline(found)).toBe('The GPU is visible inside.')
  expect(found && evidence(found)).toBe('Seen with nvidia-smi: NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB')
  const devices = parseGpuCheck({ ...smi, how: 'device nodes', detail: '/dev/nvidia0' })
  expect(devices && evidence(devices)).toBe('Seen in the device files (no nvidia-smi): /dev/nvidia0')
  const nothing = parseGpuCheck({ gpu_visible: false, how: 'none', detail: '', note: 'x' })
  expect(nothing && headline(nothing)).toBe('The GPU is not visible inside.')
  expect(nothing && evidence(nothing)).toBe('Nothing found')
})
