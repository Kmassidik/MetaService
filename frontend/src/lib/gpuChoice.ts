// The GPU part of the new-VM form and of a machine's page: what to offer (or say) for a machine and a kind, and how a workload shows that it has the GPU. Pure functions, no DOM, no network.
import { readGpuBooking, type GpuBooking } from './gpuBooking.ts'
import { gbText, gpuFreeText, gpuNote as liveNote, type GpuLive } from './gpuLive.ts'
import type { Machine, Workload } from './types.ts'

export type GpuMode = 'none' | 'container' | 'shared'

/** What the form shows about the GPU. `nothing`: no GPU on that machine (or a Mac), so there is no GPU line at all. */
export type GpuOffer =
  | { show: 'nothing' }
  | { show: 'choice'; card: string }
  | { show: 'vm_text'; text: string }
  | { show: 'needs_toolkit'; text: string }

export const VM_GPU_TEXT = "GPU in a VM is coming soon. It needs the machine's virtualization (SVM) switched on in its BIOS and the card passed through to one VM. Choose Container to use the GPU today."
export const NEEDS_TOOLKIT_TEXT = 'This machine needs the NVIDIA container toolkit first'
const NVIDIA = 'nvidia'
export const MAC_OS = 'macos'

/** One line of the GPU select. The "coming soon" lines are shown so the plan is visible, but are never picked and never sent. */
export interface GpuOption {
  value: string
  label: string
  disabled: boolean
  /** The plain sentence under the select while this line is picked; null for the lines that cannot be picked. */
  caption: string | null
}

export const SHARED_LABEL = "Shared partition — limit this VM's GPU memory"
export const HELPER_TOO_OLD_REASON = 'Update the helper on this machine first.'
export const FULLY_BOOKED_REASON = "The card's memory is fully booked."
export const FULLY_IN_USE_TEXT = 'The card is fully in use.'
export const HELD_BY_OTHER_TEXT = 'Something MetaService does not manage holds it.'
export const BOOKED_BY_VMS_TEXT = 'Its memory is booked for other VMs.'
export const CANNOT_BOOK_REASON = 'This machine cannot book GPU memory.'
export const DEFAULT_LIMIT_GB = 4
export const MIN_LIMIT_GB = 1
export const SHARED_LIMIT_HINT = 'The limit stays booked for this VM even while it is stopped.'
export const OVER_LIMIT_WARNING = 'If the VM stays over its limit for about 15 seconds it is stopped.'
export const WHOLE_NUMBER_TEXT = `GPU memory must be a whole number of GB, ${MIN_LIMIT_GB} or more.`

export const GPU_OPTIONS: readonly GpuOption[] = [
  { value: 'none', label: 'No GPU — CPU compute only', disabled: false, caption: 'No GPU is given to this VM.' },
  { value: 'container', label: 'GPU in a container — the whole card, no limit', disabled: false, caption: "The container uses the machine's GPU together with the other containers on that machine. The share is a soft limit." },
  { value: 'shared', label: SHARED_LABEL, disabled: true, caption: "The container can use only the GPU memory you set below. That memory is booked for it on the card." },
  { value: 'passthrough', label: 'Dedicated passthrough — coming soon (needs virtualization on the machine)', disabled: true, caption: null },
]

/** Whether "Shared partition" can be picked on the machine: with the card's booking, or why not (null: the container line already says why). */
export type SharedPartition = { available: true; booking: GpuBooking } | { available: false; reason: string | null }

/** The most GB a new VM can still book from the parent's booking: the whole GB of the card that is free. */
export const freeWholeGb = (booking: GpuBooking): number => Math.floor(booking.free_gb)

/** Shared partition is open exactly when GPU in a container is, the helper can limit memory, the machine reports a booking and at least 1 GB is free. */
export function sharedPartition(machine: Machine | undefined, offer: GpuOffer): SharedPartition {
  if (offer.show !== 'choice') return { available: false, reason: null }
  if (machine?.capabilities?.gpu_memory_limit !== true) return { available: false, reason: HELPER_TOO_OLD_REASON }
  const booking = readGpuBooking(machine.gpu_booking)
  if (booking === null) return { available: false, reason: CANNOT_BOOK_REASON }
  return freeWholeGb(booking) >= MIN_LIMIT_GB ? { available: true, booking } : { available: false, reason: FULLY_BOOKED_REASON }
}

/**
 * What the card can still give a new VM right now: the smaller of what the card reports free (its total less the larger of what was booked and what is
 * really used, see `gpuLive.ts`) and what the parent still lets us book. The form shows it next to the GPU choice and the number field stays under it.
 */
export interface GpuRoom {
  /** The free memory in tenths of a GB, the smaller of the two numbers; null while neither is known. */
  freeGb: number | null
  /** floor(freeGb): the most whole GB the number field may take; null while freeGb is not known. */
  capGb: number | null
  /** The card's whole memory, the number the free GB is read against; null while neither number is known. */
  totalGb: number | null
  /** "GPU: 1.8 GB free of 32 GB."; null while no number is known. */
  line: string | null
  /** The strip's sentence on the gap between booked and used; null when there is nothing to explain. */
  note: string | null
  /** "The card is fully in use." and which side holds the memory; null while a whole GB is free. */
  fullReason: string | null
}

/** The smallest of the numbers that are known; null when none is. */
function smallest(values: readonly (number | null)[]): number | null {
  const known = values.filter((value): value is number => value !== null)
  return known.length === 0 ? null : Math.min(...known)
}

/** Why nothing can be given to a new VM, in plain words: the bookings hold the memory, or something outside MetaService does. Null while a whole GB is free. */
function inUseReason(capGb: number | null, card: GpuLive | null): string | null {
  if (capGb === null || capGb >= MIN_LIMIT_GB) return null
  const held = card !== null && card.usedGb !== null && card.bookedGb < card.usedGb
  return `${FULLY_IN_USE_TEXT} ${held ? HELD_BY_OTHER_TEXT : BOOKED_BY_VMS_TEXT}`
}

/** The card's room for a new VM: the machine's live reading when it has one card, the parent's booking when it has not reported, and nothing for a machine with several cards (one strip cannot speak for all of them). */
export function gpuRoom(live: GpuLive | null, booking: GpuBooking | null): GpuRoom {
  const card = live !== null && live.cards === 1 ? live : null
  const cardFree = card?.freeGb ?? null
  const freeGb = smallest([cardFree, booking?.free_gb ?? null])
  // A booking's free GB is read against the booking's own total, never against a total the card gave without its used number.
  const totalGb = cardFree === null ? (booking?.total_gb ?? null) : card?.totalGb ?? null
  const capGb = freeGb === null ? null : Math.floor(freeGb)
  return {
    freeGb,
    capGb,
    totalGb,
    line: freeGb === null || totalGb === null ? null : `GPU: ${gpuFreeText(freeGb, totalGb)}.`,
    note: card === null ? null : liveNote(card),
    fullReason: inUseReason(capGb, card),
  }
}

/** The paragraph under the GPU select: the free memory, and then why nothing is left (or what the gap between booked and used means). Empty when nothing is known. */
export function gpuRoomText(room: GpuRoom): string {
  const parts = [room.line, room.fullReason ?? room.note].filter((part): part is string => part !== null)
  return parts.join(' ')
}

/** True when the card has no whole GB left, so neither GPU line can be picked. */
const noRoom = (room: GpuRoom | null): boolean => room !== null && room.fullReason !== null

/** What the number starts at: 4 GB, or all that the card can still give when that is less. */
export const defaultGpuMemory = (booking: GpuBooking, room: GpuRoom | null = null): number => Math.min(DEFAULT_LIMIT_GB, room?.capGb ?? freeWholeGb(booking))

/** What is wrong with the number typed for a shared partition, or null (also null while the choice is not shared). A number over the free GB names what is free and what was asked, and is never moved silently. */
export function gpuMemoryProblem(mode: string | undefined, value: unknown, sharing: SharedPartition, room: GpuRoom | null = null): string | null {
  if (mode !== 'shared' || !sharing.available) return null
  const gb = typeof value === 'string' && value.trim() !== '' ? Number(value) : value
  if (typeof gb !== 'number' || !Number.isInteger(gb) || gb < MIN_LIMIT_GB) return WHOLE_NUMBER_TEXT
  const cap = room?.capGb ?? freeWholeGb(sharing.booking)
  if (gb <= cap) return null
  if (room === null || room.freeGb === null) return `Only ${cap} GB of the card's ${sharing.booking.total_gb} GB is still free to book.`
  return `Only ${gbText(room.freeGb)} of the card is free, so ${gb} GB cannot be reserved.`
}

/** The hint under the number: what is still free to book, unless the card's own free number is already above the field, and that the booking stays. */
export function gpuMemoryHint(booking: GpuBooking, room: GpuRoom | null = null): string {
  if (room !== null && room.line !== null) return SHARED_LIMIT_HINT
  return `${freeWholeGb(booking)} GB of the card's ${booking.total_gb} GB is still free to book. ${SHARED_LIMIT_HINT}`
}

/** The sentence under the select for the mode that is picked. */
export const gpuCaption = (mode: string | undefined): string => GPU_OPTIONS.find((option) => option.value === (mode ?? 'none'))?.caption ?? ''

/** Why the shared line cannot be picked: nothing free at all first, then the line's own reason (null: the container line already says why). */
function sharedOff(sharing: SharedPartition, full: boolean): { disabled: boolean; reason: string | null } {
  if (full) return { disabled: true, reason: FULLY_IN_USE_TEXT }
  if (sharing.available) return { disabled: false, reason: null }
  return { disabled: true, reason: sharing.reason }
}

/** The lines of the GPU select: "GPU in a container" can be picked only while the offer is a real choice and the card has room, "Shared partition" only while it is available (else its reason is in brackets). */
export function gpuLines(offer: GpuOffer, sharing: SharedPartition, room: GpuRoom | null = null): GpuOption[] {
  const full = noRoom(room)
  return GPU_OPTIONS.map((option) => {
    if (option.value === 'container') return { ...option, disabled: offer.show !== 'choice' || full }
    if (option.value !== 'shared') return option
    const off = sharedOff(sharing, full)
    return { ...option, disabled: off.disabled, label: off.reason === null ? option.label : `${option.label} (${off.reason})` }
  })
}

/** The plain sentence under the GPU select: what the picked mode means, or why the container line cannot be picked. */
export function gpuNote(offer: GpuOffer, mode: string | undefined): string {
  if (offer.show === 'choice') return gpuCaption(mode)
  return offer.show === 'nothing' ? '' : offer.text
}

/** The NVIDIA card a Linux machine reports, or null. Macs never count: Apple's container tool gives no GPU to containers as far as we know. */
export function nvidiaCard(machine: Machine | undefined): string | null {
  if (!machine || machine.os === MAC_OS) return null
  return machine.gpu.find((card) => card.vendor === NVIDIA)?.model ?? null
}

/** True when the machine has an NVIDIA card but containers cannot use it, because the toolkit is not installed. */
export const needsToolkit = (machine: Machine | undefined): boolean => nvidiaCard(machine) !== null && machine?.capabilities?.gpu_in_container === false

export function gpuOffer(machine: Machine | undefined, kind: string): GpuOffer {
  const card = nvidiaCard(machine)
  if (card === null) return { show: 'nothing' }
  if (kind === 'vm') return { show: 'vm_text', text: VM_GPU_TEXT }
  if (machine?.capabilities?.gpu_in_container === true) return { show: 'choice', card }
  return { show: 'needs_toolkit', text: NEEDS_TOOLKIT_TEXT }
}

/** The mode to send: the GPU only when it was chosen, the offer is still a choice and the card has room (a changed kind, machine or full card drops it); a shared partition also needs it to be available. */
export function gpuModeToSend(offer: GpuOffer, chosen: string | undefined, sharing: SharedPartition, room: GpuRoom | null = null): GpuMode {
  if (offer.show !== 'choice') return 'none'
  if (noRoom(room)) return 'none'
  if (chosen === 'shared') return sharing.available ? 'shared' : 'none'
  return chosen === 'container' ? 'container' : 'none'
}

/** True when a workload was given the GPU (shown as a small badge). */
export const hasGpu = (workload: Pick<Workload, 'gpu_mode'>): boolean => workload.gpu_mode !== undefined && workload.gpu_mode !== 'none'

/** The note on a machine's page when it has a card the containers cannot use yet; null when there is nothing to say. */
export function toolkitNote(machine: Machine | undefined): { title: string; fix: string } | null {
  if (!needsToolkit(machine)) return null
  return {
    title: `This machine has an NVIDIA GPU (${nvidiaCard(machine)}), but containers cannot use it yet. They need NVIDIA's container toolkit (the small program that lets a container reach the GPU).`,
    fix: "On the machine, follow NVIDIA's install guide: add NVIDIA's package source, then run `sudo apt-get install -y nvidia-container-toolkit` (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). The panel notices by itself.",
  }
}
