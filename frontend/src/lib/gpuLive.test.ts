import { test, expect } from 'bun:test'
import { bookedGb, freeGb, gpuFact, gpuNote, gpuStrip, gpuTitle, readGpuLive, shortGpuName } from './gpuLive.ts'
import { cardFacts } from './cardFacts.ts'
import { machine, workload } from './testing.ts'
import type { Machine, StatsGpu } from './types.ts'

const GIB = 1024 ** 3
const gib = (gb: number): number => Math.round(gb * GIB)

/** The RTX 5090 of the production machine: 32 GB of its own, and a model server holding part of it. */
const dedicated = (usedGb: number | null, totalGb: number | null = 32): StatsGpu => ({
  name: 'NVIDIA GeForce RTX 5090', vendor: 'nvidia', utilization_percent: 40,
  memory_used_bytes: usedGb === null ? null : gib(usedGb), memory_total_bytes: totalGb === null ? null : gib(totalGb),
  temperature_celsius: 48,
})

/** A PC with the card and the VMs given to it. */
const PC = (extra: Partial<Machine> = {}): Machine => machine({
  id: 'pc', os: 'linux', arch: 'x86_64', gpu: [{ vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090', memory_mb: 32607 }], ...extra,
})

/** A VM with a limit on its part of the card. */
const booking = (id: string, gb: number) => workload({ id, gpu_mode: 'container', gpu_memory_gb: gb })

/** The strip as the Live tab writes it, for a machine and the GPUs of its reading (none when it has not reported). */
const strip = (m: Machine, ...gpus: StatsGpu[]): string | null => {
  const live = readGpuLive(m, gpus)
  return live === null ? null : gpuStrip(live)
}

/** The one sentence about the gap between booked and used, or null. */
const note = (m: Machine, ...gpus: StatsGpu[]): string | null => {
  const live = readGpuLive(m, gpus)
  return live === null ? null : gpuNote(live)
}

test('free is the total less the larger of what was booked and what is really used, never below 0', () => {
  expect(freeGb(32, 30.2, 2)).toBe(1.8)
  expect(freeGb(32, 2, 30.2)).toBe(1.8)
  expect(freeGb(32, 4, 4)).toBe(28)
  expect(freeGb(32, 33, 0)).toBe(0)
  expect(freeGb(32, 0, 40)).toBe(0)
})

test('no number is invented: a missing total or used memory leaves free unknown', () => {
  expect(freeGb(null, 4, 2)).toBeNull()
  expect(freeGb(32, null, 2)).toBeNull()
})

test('booked is the sum of the VMs limits, and the parent booking when it promises more', () => {
  expect(bookedGb(PC({ workloads: [booking('a', 2), booking('b', 6)] }))).toBe(8)
  expect(bookedGb(PC({ workloads: [booking('a', 2), workload({ id: 'b' })] }))).toBe(2)
  expect(bookedGb(PC())).toBe(0)
  expect(bookedGb(PC({ gpu_booking: { total_gb: 32, booked_gb: 6, free_gb: 26 } }))).toBe(6)
  expect(bookedGb(PC({ workloads: [booking('a', 8)], gpu_booking: { total_gb: 32, booked_gb: 6, free_gb: 26 } }))).toBe(8)
})

test('booked only: the strip says the memory is reserved and not yet taken', () => {
  expect(strip(PC({ workloads: [booking('a', 2)] }), dedicated(0.4))).toBe('GPU RTX 5090 · 32 GB total · 2 GB booked · 0.4 GB used · 30 GB free')
  expect(note(PC({ workloads: [booking('a', 2)] }), dedicated(0.4))).toBe('1.6 GB reserved by bookings, not yet used.')
})

test('used only: the strip says something MetaService does not manage holds the memory', () => {
  expect(strip(PC(), dedicated(30.2))).toBe('GPU RTX 5090 · 32 GB total · 0 GB booked · 30.2 GB used · 1.8 GB free')
  expect(note(PC(), dedicated(30.2))).toBe('30.2 GB used by something MetaService does not manage.')
})

test('both: the booking and the programs are named, and free counts the programs', () => {
  const pc = PC({ workloads: [booking('a', 2)] })
  expect(strip(pc, dedicated(30.2))).toBe('GPU RTX 5090 · 32 GB total · 2 GB booked · 30.2 GB used · 1.8 GB free')
  expect(note(pc, dedicated(30.2))).toBe('28.2 GB used by something MetaService does not manage.')
})

test('booked and used the same: nothing to explain, and free is the rest', () => {
  const pc = PC({ workloads: [booking('a', 4)] })
  expect(strip(pc, dedicated(4))).toBe('GPU RTX 5090 · 32 GB total · 4 GB booked · 4 GB used · 28 GB free')
  expect(note(pc, dedicated(4))).toBeNull()
})

test('nothing booked and nothing used: the whole card is free', () => {
  expect(strip(PC(), dedicated(0))).toBe('GPU RTX 5090 · 32 GB total · 0 GB booked · 0 GB used · 32 GB free')
  expect(note(PC(), dedicated(0))).toBeNull()
})

test('a machine that is off or has not reported yet: the name and a dash, no free number', () => {
  expect(strip(PC({ workloads: [booking('a', 2)] }))).toBe('GPU RTX 5090 · —')
  expect(note(PC({ workloads: [booking('a', 2)] }))).toBeNull()
  expect(gpuFact(readGpuLive(PC(), [])!)).toBeNull()
})

test('a machine that is off under its last reading keeps the card but none of its numbers', () => {
  const off = readGpuLive(PC({ workloads: [booking('a', 2)] }), [dedicated(30.2)], false)!
  expect(gpuStrip(off)).toBe('GPU RTX 5090 · —')
  expect(off.freeGb).toBeNull()
  expect(gpuNote(off)).toBeNull()
})

test('a card whose used memory cannot be read keeps the total and dashes the rest', () => {
  expect(strip(PC({ workloads: [booking('a', 2)] }), dedicated(null))).toBe('GPU RTX 5090 · 32 GB total · 2 GB booked · — used · — free')
  expect(gpuFact(readGpuLive(PC(), [dedicated(null)])!)).toBeNull()
})

test('a machine with no GPU has no strip at all', () => {
  const mac = machine({ id: 'mac', gpu: [] })
  expect(readGpuLive(mac, [])).toBeNull()
  expect(strip(mac)).toBeNull()
  expect(cardFacts(mac).find((fact) => fact.key === 'gpu')?.value).toBe('—')
})

test('a machine whose own list names no card still gets the strip from its reading', () => {
  const unlisted = machine({ id: 'unlisted', gpu: [] })
  expect(strip(unlisted, dedicated(30.2))).toBe('GPU RTX 5090 · 32 GB total · 0 GB booked · 30.2 GB used · 1.8 GB free')
  expect(readGpuLive(unlisted, [])).toBeNull()
})

test('the card keeps one short value, and its names list when the machine has more than one card', () => {
  const live = readGpuLive(PC({ workloads: [booking('a', 2)] }), [dedicated(30.2)])!
  expect(gpuFact(live)).toBe('RTX 5090 · 1.8 GB free of 32 GB')
  expect(cardFacts(PC({ workloads: [booking('a', 2)] }), gpuFact(live)).find((fact) => fact.key === 'gpu')?.value).toBe('RTX 5090 · 1.8 GB free of 32 GB')
  const duo = machine({ gpu: [{ vendor: 'nvidia', model: 'NVIDIA GeForce RTX 5090' }, { vendor: 'amd', model: 'AMD Radeon RX 7900 XTX', memory_mb: 24560 }] })
  const twoCards = readGpuLive(duo, [dedicated(4)])!
  expect(gpuFact(twoCards)).toBeNull()
  expect(gpuStrip(twoCards)).toContain('GPU RTX 5090')
  expect(cardFacts(duo).find((fact) => fact.key === 'gpu')?.value).toBe('NVIDIA GeForce RTX 5090, AMD Radeon RX 7900 XTX')
})

test('the hover text of the card row is the whole strip and the sentence about the gap', () => {
  const live = readGpuLive(PC(), [dedicated(30.2)])!
  expect(gpuTitle(live)).toBe('GPU RTX 5090 · 32 GB total · 0 GB booked · 30.2 GB used · 1.8 GB free. 30.2 GB used by something MetaService does not manage.')
})

test('the card is named in short, and a name of maker words only is kept whole', () => {
  expect(shortGpuName('NVIDIA GeForce RTX 5090')).toBe('RTX 5090')
  expect(shortGpuName('NVIDIA GB10')).toBe('GB10')
  expect(shortGpuName('AMD Radeon RX 7900 XTX')).toBe('RX 7900 XTX')
  expect(shortGpuName('Apple M3 Max GPU')).toBe('M3 Max GPU')
  expect(shortGpuName('NVIDIA')).toBe('NVIDIA')
})
