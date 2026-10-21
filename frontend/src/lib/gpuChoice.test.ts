import { test, expect } from 'bun:test'
import { gpuModeToSend, gpuOffer, hasGpu, needsToolkit, nvidiaCard, toolkitNote, VM_GPU_TEXT, NEEDS_TOOLKIT_TEXT } from './gpuChoice.ts'
import { machine, workload } from './testing.ts'

const card = { vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090' }
const caps = (gpu_in_container: boolean) => ({ vm: false, container: true, gpu_in_vm: false, gpu_in_container })
const rtx = machine({ os: 'linux', arch: 'x86_64', gpu: [card], capabilities: caps(true) })
const noToolkit = machine({ os: 'linux', arch: 'x86_64', gpu: [card], capabilities: caps(false) })
const mac = machine({ os: 'macos', gpu: [{ vendor: 'apple', model: 'Apple M2' }], capabilities: caps(false) })

test('a machine with a card and the toolkit offers the choice for a container', () => {
  expect(gpuOffer(rtx, 'container')).toEqual({ show: 'choice', card: 'NVIDIA GeForce RTX 5090' })
})

test('for a VM there is only the plain text, never a control', () => {
  expect(gpuOffer(rtx, 'vm')).toEqual({ show: 'vm_text', text: VM_GPU_TEXT })
  expect(VM_GPU_TEXT).toBe('A VM cannot use the GPU yet: that needs virtualization turned on in the BIOS (SVM) and the card passed through to one VM.')
})

test('a card without the toolkit says the machine needs it first', () => {
  expect(gpuOffer(noToolkit, 'container')).toEqual({ show: 'needs_toolkit', text: NEEDS_TOOLKIT_TEXT })
  expect(needsToolkit(noToolkit)).toBe(true)
  expect(needsToolkit(rtx)).toBe(false)
})

test('a Mac, a machine with no card and no machine at all get nothing', () => {
  for (const kind of ['vm', 'container']) {
    expect(gpuOffer(mac, kind)).toEqual({ show: 'nothing' })
    expect(gpuOffer(machine({ os: 'linux', gpu: [] }), kind)).toEqual({ show: 'nothing' })
    expect(gpuOffer(undefined, kind)).toEqual({ show: 'nothing' })
  }
  expect(nvidiaCard(machine({ os: 'macos', gpu: [card] }))).toBeNull()
  expect(nvidiaCard(machine({ os: 'linux', gpu: [{ vendor: 'amd', model: 'Radeon' }] }))).toBeNull()
})

test('the GPU is sent only when it was chosen and is still offered', () => {
  const choice = gpuOffer(rtx, 'container')
  expect(gpuModeToSend(choice, 'container')).toBe('container')
  expect(gpuModeToSend(choice, 'none')).toBe('none')
  expect(gpuModeToSend(choice, undefined)).toBe('none')
  expect(gpuModeToSend(gpuOffer(rtx, 'vm'), 'container')).toBe('none')
  expect(gpuModeToSend(gpuOffer(noToolkit, 'container'), 'container')).toBe('none')
})

test('a workload has the badge only when it was given the GPU', () => {
  expect(hasGpu(workload({ gpu_mode: 'container' }))).toBe(true)
  expect(hasGpu(workload({ gpu_mode: 'none' }))).toBe(false)
  expect(hasGpu(workload())).toBe(false)
})

test('the machine page note appears only for a card the containers cannot use yet', () => {
  expect(toolkitNote(rtx)).toBeNull()
  expect(toolkitNote(mac)).toBeNull()
  const note = toolkitNote(noToolkit)
  expect(note?.title).toContain('RTX 5090')
  expect(note?.fix).toContain('apt-get install -y nvidia-container-toolkit')
})
