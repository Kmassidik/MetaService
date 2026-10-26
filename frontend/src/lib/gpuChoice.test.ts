import { test, expect } from 'bun:test'
import { GPU_OPTIONS, gpuCaption, gpuLines, gpuModeToSend, gpuNote, gpuOffer, gpuRoom, gpuRoomText, hasGpu, needsToolkit, nvidiaCard, sharedPartition, defaultGpuMemory, gpuMemoryHint, gpuMemoryProblem, OVER_LIMIT_WARNING, toolkitNote, VM_GPU_TEXT, NEEDS_TOOLKIT_TEXT, SHARED_LABEL, type SharedPartition } from './gpuChoice.ts'
import { readGpuLive, type GpuLive } from './gpuLive.ts'
import { machine, workload } from './testing.ts'
import type { StatsGpu } from './types.ts'

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

const GIB = 1024 ** 3
const gib = (gb: number): number => Math.round(gb * GIB)
/** The RTX 5090 of the production machine as one reading: 32 GB of its own, and whatever is held right now. */
const reading = (usedGb: number | null, totalGb: number | null = 32): StatsGpu => ({
  name: 'NVIDIA GeForce RTX 5090', vendor: 'nvidia', utilization_percent: 40, temperature_celsius: 48,
  memory_used_bytes: usedGb === null ? null : gib(usedGb), memory_total_bytes: totalGb === null ? null : gib(totalGb),
})
/** A machine with the card and a VM booking of `booked` GB (none when left out), read against the given reading. */
const live = (gpu: StatsGpu, booked?: number): GpuLive => {
  const read = readGpuLive(machine({ os: 'linux', arch: 'x86_64', gpu: [card], workloads: booked === undefined ? [] : [workload({ id: 'a', gpu_mode: 'container', gpu_memory_gb: booked })] }), [gpu])
  if (read === null) throw new Error('the test machine has a card')
  return read
}
const FREE_18 = gpuRoom(live(reading(30.2)), null)
const FULL = gpuRoom(live(reading(32)), null)

test('a card nothing booked and nothing else uses is free to the last GB', () => {
  const room = gpuRoom(live(reading(0)), null)
  expect(room).toMatchObject({ freeGb: 32, capGb: 32, totalGb: 32, line: 'GPU: 32 GB free of 32 GB.', note: null, fullReason: null })
  expect(gpuRoomText(room)).toBe('GPU: 32 GB free of 32 GB.')
})

test('booked only: the note says the memory is reserved and not yet used, and free counts the booking', () => {
  const room = gpuRoom(live(reading(0.4), 2), null)
  expect(room).toMatchObject({ freeGb: 30, capGb: 30, line: 'GPU: 30 GB free of 32 GB.', note: '1.6 GB reserved by bookings, not yet used.' })
  expect(gpuRoomText(room)).toBe('GPU: 30 GB free of 32 GB. 1.6 GB reserved by bookings, not yet used.')
})

test('used only: something MetaService does not manage holds the card, and that is what free counts', () => {
  expect(FREE_18).toMatchObject({ freeGb: 1.8, capGb: 1, totalGb: 32, line: 'GPU: 1.8 GB free of 32 GB.', note: '30.2 GB used by something MetaService does not manage.', fullReason: null })
  expect(gpuRoomText(FREE_18)).toBe('GPU: 1.8 GB free of 32 GB. 30.2 GB used by something MetaService does not manage.')
})

test('both: the programs are named, and the smaller of the card and the booking wins', () => {
  expect(gpuRoom(live(reading(30.2), 2), booking(23))).toMatchObject({ freeGb: 1.8, capGb: 1, note: '28.2 GB used by something MetaService does not manage.' })
})

test('a full card says so, and names what holds it', () => {
  expect(FULL).toMatchObject({ freeGb: 0, capGb: 0, line: 'GPU: 0 GB free of 32 GB.', fullReason: 'The card is fully in use. Something MetaService does not manage holds it.' })
  expect(gpuRoomText(FULL)).toBe('GPU: 0 GB free of 32 GB. The card is fully in use. Something MetaService does not manage holds it.')
  expect(gpuRoom(null, { total_gb: 32, booked_gb: 32, free_gb: 0 })).toMatchObject({ freeGb: 0, capGb: 0, line: 'GPU: 0 GB free of 32 GB.', note: null, fullReason: 'The card is fully in use. Its memory is booked for other VMs.' })
})

test('no reading: the parent booking speaks alone, and nothing is known without it', () => {
  expect(gpuRoom(live(reading(null)), booking(23))).toMatchObject({ freeGb: 23, capGb: 23, totalGb: 31, line: 'GPU: 23 GB free of 31 GB.', note: null, fullReason: null })
  expect(gpuRoom(null, null)).toEqual({ freeGb: null, capGb: null, totalGb: null, line: null, note: null, fullReason: null })
  expect(gpuRoomText(gpuRoom(null, null))).toBe('')
})

test('a machine with two cards leaves the strip to the booking, not to the first card', () => {
  const two = readGpuLive(machine({ os: 'linux', arch: 'x86_64', gpu: [card, card] }), [reading(30.2), reading(0)])
  expect(gpuRoom(two, booking(23))).toMatchObject({ freeGb: 23, capGb: 23, line: 'GPU: 23 GB free of 31 GB.', note: null })
})

test('the number starts at 4 GB, or at what the card can still give', () => {
  expect(defaultGpuMemory(booking(23), gpuRoom(null, booking(23)))).toBe(4)
  expect(defaultGpuMemory(booking(23), FREE_18)).toBe(1)
  expect(defaultGpuMemory(booking(3), null)).toBe(3)
  expect(defaultGpuMemory(booking(23))).toBe(4)
})

test("a number over the card's free GB is refused in words that name both numbers", () => {
  const sharing: SharedPartition = { available: true, booking: booking(23) }
  expect(gpuMemoryProblem('shared', 1, sharing, FREE_18)).toBeNull()
  expect(gpuMemoryProblem('shared', 4, sharing, FREE_18)).toBe('Only 1.8 GB of the card is free, so 4 GB cannot be reserved.')
  expect(gpuMemoryProblem('shared', 2, sharing, FULL)).toBe('Only 0 GB of the card is free, so 2 GB cannot be reserved.')
  expect(gpuMemoryProblem('shared', 24, sharing, gpuRoom(null, booking(23)))).toBe('Only 23 GB of the card is free, so 24 GB cannot be reserved.')
  expect(gpuMemoryProblem('shared', 24, sharing)).toBe("Only 23 GB of the card's 31 GB is still free to book.")
})

test('a full card greys both GPU lines with the plain sentence and sends no GPU at all', () => {
  const offer = gpuOffer(rtx, 'container')
  const sharing: SharedPartition = { available: true, booking: booking(23) }
  const lines = gpuLines(offer, sharing, FULL)
  expect(lines.map((line) => [line.value, line.disabled])).toEqual([['none', false], ['container', true], ['shared', true], ['passthrough', true]])
  expect(lines.find((line) => line.value === 'shared')?.label).toBe(`${SHARED_LABEL} (The card is fully in use.)`)
  expect(gpuModeToSend(offer, 'container', sharing, FULL)).toBe('none')
  expect(gpuModeToSend(offer, 'shared', sharing, FULL)).toBe('none')
  expect(gpuModeToSend(offer, 'container', sharing, FREE_18)).toBe('container')
  expect(gpuModeToSend(offer, 'shared', sharing, FREE_18)).toBe('shared')
  expect(gpuLines(offer, sharing, FREE_18).filter((line) => line.disabled).map((line) => line.value)).toEqual(['passthrough'])
})

test('the hint under the number does not repeat the line above it, and keeps the booking sentence', () => {
  expect(gpuMemoryHint(booking(23), FREE_18)).toBe('The limit stays booked for this VM even while it is stopped.')
  expect(gpuMemoryHint(booking(23))).toBe("23 GB of the card's 31 GB is still free to book. The limit stays booked for this VM even while it is stopped.")
})
