import { test, expect } from 'bun:test'
import { GPU_OPTIONS, gpuCaption, gpuLines, gpuModeToSend, gpuNote, gpuOffer, hasGpu, needsToolkit, nvidiaCard, sharedPartition, defaultGpuMemory, gpuMemoryHint, gpuMemoryProblem, OVER_LIMIT_WARNING, toolkitNote, VM_GPU_TEXT, NEEDS_TOOLKIT_TEXT, type SharedPartition } from './gpuChoice.ts'
import { machine, workload } from './testing.ts'

const card = { vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090' }
const caps = (gpu_in_container: boolean) => ({ vm: false, container: true, gpu_in_vm: false, gpu_in_container })
const rtx = machine({ os: 'linux', arch: 'x86_64', gpu: [card], capabilities: caps(true) })
const noToolkit = machine({ os: 'linux', arch: 'x86_64', gpu: [card], capabilities: caps(false) })
const NO_SHARING: SharedPartition = { available: false, reason: null }
const mac = machine({ os: 'macos', gpu: [{ vendor: 'apple', model: 'Apple M2' }], capabilities: caps(false) })

test('a machine with a card and the toolkit offers the choice for a container', () => {
  expect(gpuOffer(rtx, 'container')).toEqual({ show: 'choice', card: 'NVIDIA GeForce RTX 5090' })
})

test('for a VM the offer is the plain text, and the container line cannot be picked', () => {
  expect(gpuOffer(rtx, 'vm')).toEqual({ show: 'vm_text', text: VM_GPU_TEXT })
  expect(VM_GPU_TEXT).toBe("GPU in a VM is coming soon. It needs the machine's virtualization (SVM) switched on in its BIOS and the card passed through to one VM. Choose Container to use the GPU today.")
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
  expect(gpuModeToSend(choice, 'container', NO_SHARING)).toBe('container')
  expect(gpuModeToSend(choice, 'none', NO_SHARING)).toBe('none')
  expect(gpuModeToSend(choice, undefined, NO_SHARING)).toBe('none')
  expect(gpuModeToSend(gpuOffer(rtx, 'vm'), 'container', NO_SHARING)).toBe('none')
  expect(gpuModeToSend(gpuOffer(noToolkit, 'container'), 'container', NO_SHARING)).toBe('none')
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

test('the GPU select lists No GPU, the container, the shared partition and the planned passthrough, in that order', () => {
  expect(GPU_OPTIONS.map((option) => `${option.value}:${option.disabled ? 'off' : 'on'}`)).toEqual(['none:on', 'container:on', 'shared:off', 'passthrough:off'])
  expect(GPU_OPTIONS.map((option) => option.label)).toEqual([
    'No GPU — CPU compute only',
    'GPU in a container — the whole card, no limit',
    "Shared partition — limit this VM's GPU memory",
    'Dedicated passthrough — coming soon (needs virtualization on the machine)',
  ])
})

test('the line under the GPU select explains the mode that is picked', () => {
  expect(gpuCaption(undefined)).toBe('No GPU is given to this VM.')
  expect(gpuCaption('container')).toBe("The container uses the machine's GPU together with the other containers on that machine. The share is a soft limit.")
  expect(gpuCaption('shared')).toContain('only the GPU memory you set')
  expect(gpuCaption('custom')).toBe('')
})

test('a planned mode is never sent, even if it reached the form', () => {
  const offer = gpuOffer(rtx, 'container')
  expect(['passthrough', 'custom'].map((mode) => gpuModeToSend(offer, mode, NO_SHARING))).toEqual(['none', 'none'])
})

test('the GPU select is listed for every machine with a card, and the container line can be picked only when it is a real choice', () => {
  const container = (offer: ReturnType<typeof gpuOffer>) => gpuLines(offer, NO_SHARING).find((line) => line.value === 'container')?.disabled
  expect(container(gpuOffer(rtx, 'container'))).toBe(false)
  expect(container(gpuOffer(rtx, 'vm'))).toBe(true)
  expect(container(gpuOffer(noToolkit, 'container'))).toBe(true)
  expect(gpuLines(gpuOffer(rtx, 'vm'), NO_SHARING).map((line) => [line.value, line.disabled])).toEqual([['none', false], ['container', true], ['shared', true], ['passthrough', true]])
})

test('the sentence under the select explains the choice, or why the container line is off', () => {
  expect(gpuNote(gpuOffer(rtx, 'container'), 'none')).toBe('No GPU is given to this VM.')
  expect(gpuNote(gpuOffer(rtx, 'vm'), 'none')).toBe(VM_GPU_TEXT)
  expect(gpuNote(gpuOffer(noToolkit, 'container'), undefined)).toBe(NEEDS_TOOLKIT_TEXT)
  expect(gpuNote(gpuOffer(mac, 'vm'), undefined)).toBe('')
})

const booking = (free: number) => ({ total_gb: 31, booked_gb: 31 - free, free_gb: free })
const sharer = (extra: Parameters<typeof machine>[0] = {}) => machine({ os: 'linux', arch: 'x86_64', gpu: [card], capabilities: { ...caps(true), gpu_memory_limit: true }, gpu_booking: booking(23), ...extra })

test('shared partition is open exactly when the container is, the helper can limit, a booking is known and 1 GB is free', () => {
  const open = sharedPartition(sharer(), gpuOffer(sharer(), 'container'))
  expect(open).toEqual({ available: true, booking: booking(23) })
  expect(sharedPartition(sharer({ gpu_booking: booking(1) }), gpuOffer(rtx, 'container')).available).toBe(true)
})

test('each reason shared partition is off is plain, in the order: old helper, no booking, fully booked', () => {
  const offer = gpuOffer(sharer(), 'container')
  expect(sharedPartition(sharer({ capabilities: { ...caps(true), gpu_memory_limit: false } }), offer)).toEqual({ available: false, reason: 'Update the helper on this machine first.' })
  expect(sharedPartition(rtx, offer)).toEqual({ available: false, reason: 'Update the helper on this machine first.' })
  expect(sharedPartition(sharer({ gpu_booking: null }), offer)).toEqual({ available: false, reason: 'This machine cannot book GPU memory.' })
  expect(sharedPartition(sharer({ gpu_booking: { total_gb: 'x' } }), offer)).toEqual({ available: false, reason: 'This machine cannot book GPU memory.' })
  expect(sharedPartition(sharer({ gpu_booking: booking(0) }), offer)).toEqual({ available: false, reason: "The card's memory is fully booked." })
  expect(sharedPartition(sharer({ gpu_booking: booking(0.5) }), offer)).toEqual({ available: false, reason: "The card's memory is fully booked." })
})

test('shared partition is off without a reason while the container line itself is off', () => {
  expect(sharedPartition(sharer(), gpuOffer(sharer(), 'vm'))).toEqual({ available: false, reason: null })
  expect(sharedPartition(sharer({ capabilities: { ...caps(false), gpu_memory_limit: true } }), gpuOffer(noToolkit, 'container'))).toEqual({ available: false, reason: null })
})

test('the shared line is enabled with the booking and carries its reason in brackets when off', () => {
  const offer = gpuOffer(rtx, 'container')
  const line = (sharing: SharedPartition) => gpuLines(offer, sharing).find((entry) => entry.value === 'shared')
  expect(line({ available: true, booking: booking(23) })).toMatchObject({ disabled: false, label: "Shared partition — limit this VM's GPU memory" })
  expect(line({ available: false, reason: 'Update the helper on this machine first.' })).toMatchObject({ disabled: true, label: "Shared partition — limit this VM's GPU memory (Update the helper on this machine first.)" })
  expect(line({ available: false, reason: null })?.label).toBe("Shared partition — limit this VM's GPU memory")
})

test('a shared partition is sent only while it is available', () => {
  const offer = gpuOffer(rtx, 'container')
  expect(gpuModeToSend(offer, 'shared', { available: true, booking: booking(23) })).toBe('shared')
  expect(gpuModeToSend(offer, 'shared', NO_SHARING)).toBe('none')
  expect(gpuModeToSend(gpuOffer(rtx, 'vm'), 'shared', { available: true, booking: booking(23) })).toBe('none')
})

test('the number starts at 4 GB, or at what is free when that is less', () => {
  expect(defaultGpuMemory(booking(23))).toBe(4)
  expect(defaultGpuMemory(booking(3))).toBe(3)
  expect(defaultGpuMemory(booking(2.9))).toBe(2)
})

test('the number is checked live: a whole number from 1 to the free GB', () => {
  const sharing: SharedPartition = { available: true, booking: booking(23) }
  for (const good of [1, 4, 23, '8']) expect(gpuMemoryProblem('shared', good, sharing)).toBeNull()
  for (const bad of [0, -1, 2.5, null, undefined, '', 'abc', Number.NaN]) expect(gpuMemoryProblem('shared', bad, sharing)).toBe('GPU memory must be a whole number of GB, 1 or more.')
  expect(gpuMemoryProblem('shared', 24, sharing)).toBe("Only 23 GB of the card's 31 GB is still free to book.")
  expect(gpuMemoryProblem('container', 999, sharing)).toBeNull()
  expect(gpuMemoryProblem('shared', 999, NO_SHARING)).toBeNull()
})

test('the hint under the number says what is free and that the booking stays', () => {
  expect(gpuMemoryHint(booking(23))).toBe("23 GB of the card's 31 GB is still free to book. The limit stays booked for this VM even while it is stopped.")
  expect(OVER_LIMIT_WARNING).toBe('If the VM stays over its limit for about 15 seconds it is stopped.')
})
