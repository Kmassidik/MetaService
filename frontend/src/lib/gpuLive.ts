// The GPU strip: what the card has, what MetaService has booked, what is really used, and therefore what is free. Pure functions, no DOM, no network.
// "Booked" is the memory promised to VMs. "Used" is what everything on the machine holds now, MetaService's own work and anything else with it. The free
// number is taken from the larger of the two, so the strip never promises memory another program already holds (a model server holding 29 GB of a 32 GB card).
import { UNKNOWN } from './cardFacts.ts'
import { readGpuBooking, readGpuMemoryGb } from './gpuBooking.ts'
import { gpuName } from './hardware.ts'
import type { Machine, StatsGpu } from './types.ts'

const BYTES_PER_GIB = 1024 ** 3
/** The strip's numbers are tenths of a GB, so the four of them still add up in the reader's head. */
const TENTHS = 10
/** The maker and family words a card's name drops to stay short: "NVIDIA GeForce RTX 5090" is "RTX 5090". */
const DROPPED_WORDS = new Set(['nvidia', 'geforce', 'amd', 'radeon', 'intel', 'apple'])
const SEPARATOR = ' · '

/** A machine's card as the panel shows it right now: the numbers it knows, and the ones the machine has not reported as null. */
export interface GpuLive {
  /** The card in short: "RTX 5090". */
  name: string
  /** How many cards the machine has: a card of a machine with several keeps its list of names instead of one card's numbers. */
  cards: number
  /** What MetaService booked on the card, in whole GB. */
  bookedGb: number
  /** The whole card's memory; null while the machine has not reported. */
  totalGb: number | null
  /** What everything on the machine holds now; null while the machine has not reported. */
  usedGb: number | null
  /** total − max(booked, used), never below 0; null while either of the two is missing. */
  freeGb: number | null
}

/** A tenth of a GB is as fine as the strip goes; rounding every number once keeps them adding up when read. */
const tenths = (gb: number): number => Math.round(gb * TENTHS) / TENTHS
/** A GB with at most one decimal, as the panel writes sizes: "2 GB", "30.2 GB". */
const amount = (gb: number): string => `${tenths(gb)} GB`
const shown = (gb: number | null): string => (gb === null ? UNKNOWN : amount(gb))

/** A reading's bytes as GB in tenths; null when the machine gave no number. */
const tenthsOfGb = (bytes: number | null): number | null => (bytes === null ? null : tenths(bytes / BYTES_PER_GIB))

/** A card's own memory: a total of 0 is a card with none to report (a Mac, or a helper that does not say), not an empty card. */
const cardTotalGb = (bytes: number | null): number | null => (bytes === null || bytes <= 0 ? null : tenthsOfGb(bytes))

/** "NVIDIA GeForce RTX 5090" -> "RTX 5090". A name made only of maker words is kept whole, so a card is never left unnamed. */
export function shortGpuName(fullName: string): string {
  const kept = fullName.split(' ').filter((word) => word !== '' && !DROPPED_WORDS.has(word.toLowerCase()))
  return kept.length === 0 ? fullName : kept.join(' ')
}

/** The card in short: the machine's own list names it even while the machine is off; a reading names it when the machine's list does not. Null when neither does. */
function cardName(machine: Machine, card: StatsGpu | undefined): string | null {
  const listed = machine.gpu[0]
  if (listed !== undefined) return shortGpuName(gpuName(listed))
  return card === undefined ? null : shortGpuName(card.name)
}

/** What MetaService has promised on a machine's card: the sum of the VMs' limits, or the parent's own booking when that is more (a create still running holds memory no VM shows yet). */
export function bookedGb(machine: Machine): number {
  const limits = machine.workloads.reduce((sum, workload) => sum + (readGpuMemoryGb(workload.gpu_memory_gb) ?? 0), 0)
  const promised = readGpuBooking(machine.gpu_booking)?.booked_gb ?? 0
  return Math.max(limits, promised)
}

/** The memory no one holds: the total less the larger of what was booked and what is really used, and never below 0. Null while a number is missing. */
export function freeGb(totalGb: number | null, usedGb: number | null, booked: number): number | null {
  if (totalGb === null || usedGb === null) return null
  return tenths(Math.max(0, totalGb - Math.max(booked, usedGb)))
}

/** A machine's card with its live numbers, or null for a machine without a GPU. `gpus` is the GPU list of the live reading (empty when there is none), and `reporting` false is a machine that is off or too old to answer: the card is still named, and none of its numbers are shown. */
export function readGpuLive(machine: Machine, gpus: readonly StatsGpu[], reporting = true): GpuLive | null {
  const [card] = gpus
  const name = cardName(machine, card)
  if (name === null) return null
  const totalGb = reporting ? cardTotalGb(card?.memory_total_bytes ?? null) : null
  const usedGb = reporting ? tenthsOfGb(card?.memory_used_bytes ?? null) : null
  const booked = bookedGb(machine)
  return { name, cards: Math.max(machine.gpu.length, gpus.length), bookedGb: booked, totalGb, usedGb, freeGb: freeGb(totalGb, usedGb, booked) }
}

/** "GPU RTX 5090 · 32 GB total · 2 GB booked · 30.2 GB used · 1.8 GB free"; the card's name and a dash for a machine that has not reported. */
export function gpuStrip(gpu: GpuLive): string {
  if (gpu.totalGb === null) return `GPU ${gpu.name}${SEPARATOR}${UNKNOWN}`
  return [`GPU ${gpu.name}`, `${amount(gpu.totalGb)} total`, `${amount(gpu.bookedGb)} booked`, `${shown(gpu.usedGb)} used`, `${shown(gpu.freeGb)} free`].join(SEPARATOR)
}

/** The plain sentence for the gap between booked and used: the memory promised and not yet taken, or the memory taken that nothing booked. Null when the two match or the machine has not reported. */
export function gpuNote(gpu: GpuLive): string | null {
  if (gpu.usedGb === null) return null
  if (gpu.bookedGb > gpu.usedGb) return `${amount(gpu.bookedGb - gpu.usedGb)} reserved by bookings, not yet used.`
  if (gpu.usedGb > gpu.bookedGb) return `${amount(gpu.usedGb - gpu.bookedGb)} used by something MetaService does not manage.`
  return null
}

/** The card's one row when the whole strip does not fit: "RTX 5090 · 1.8 GB free of 32 GB". Null when the numbers are not there, or the machine has more than one card. */
export function gpuFact(gpu: GpuLive): string | null {
  if (gpu.cards > 1 || gpu.totalGb === null || gpu.freeGb === null) return null
  return `${gpu.name}${SEPARATOR}${amount(gpu.freeGb)} free of ${amount(gpu.totalGb)}`
}

/** The hover text of the card's GPU row: the whole strip and what the gap between its numbers means. */
export function gpuTitle(gpu: GpuLive): string {
  const note = gpuNote(gpu)
  return note === null ? gpuStrip(gpu) : `${gpuStrip(gpu)}. ${note}`
}
