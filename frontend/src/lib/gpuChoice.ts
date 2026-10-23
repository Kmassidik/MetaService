// The GPU part of the new-VM form and of a machine's page: what to offer (or say) for a machine and a kind, and how a workload shows that it has the GPU. Pure functions, no DOM, no network.
import { readGpuBooking, type GpuBooking } from './gpuBooking.ts'
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
export const CANNOT_BOOK_REASON = 'This machine cannot book GPU memory.'
export const DEFAULT_LIMIT_GB = 4
export const MIN_LIMIT_GB = 1
export const SHARED_LIMIT_HINT = 'The limit stays booked for this VM even while it is stopped.'
export const OVER_LIMIT_WARNING = 'If the VM stays over its limit for about 15 seconds it is stopped.'

export const GPU_OPTIONS: readonly GpuOption[] = [
  { value: 'none', label: 'No GPU — CPU compute only', disabled: false, caption: 'No GPU is given to this VM.' },
  { value: 'container', label: 'GPU in a container — the whole card, no limit', disabled: false, caption: "The container uses the machine's GPU together with the other containers on that machine. The share is a soft limit." },
  { value: 'shared', label: SHARED_LABEL, disabled: true, caption: "The container can use only the GPU memory you set below. That memory is booked for it on the card." },
  { value: 'passthrough', label: 'Dedicated passthrough — coming soon (needs virtualization on the machine)', disabled: true, caption: null },
]

/** Whether "Shared partition" can be picked on the machine: with the card's booking, or why not (null: the container line already says why). */
export type SharedPartition = { available: true; booking: GpuBooking } | { available: false; reason: string | null }

/** The most GB a new VM can still book: the whole GB of the card that is free. */
export const freeWholeGb = (booking: GpuBooking): number => Math.floor(booking.free_gb)

/** Shared partition is open exactly when GPU in a container is, the helper can limit memory, the machine reports a booking and at least 1 GB is free. */
export function sharedPartition(machine: Machine | undefined, offer: GpuOffer): SharedPartition {
  if (offer.show !== 'choice') return { available: false, reason: null }
  if (machine?.capabilities?.gpu_memory_limit !== true) return { available: false, reason: HELPER_TOO_OLD_REASON }
  const booking = readGpuBooking(machine.gpu_booking)
  if (booking === null) return { available: false, reason: CANNOT_BOOK_REASON }
  return freeWholeGb(booking) >= MIN_LIMIT_GB ? { available: true, booking } : { available: false, reason: FULLY_BOOKED_REASON }
}

/** What the number starts at: 4 GB, or all that is free when that is less. */
export const defaultGpuMemory = (booking: GpuBooking): number => Math.min(DEFAULT_LIMIT_GB, freeWholeGb(booking))

/** What is wrong with the number typed for a shared partition, or null (also null while the choice is not shared). */
export function gpuMemoryProblem(mode: string | undefined, value: unknown, sharing: SharedPartition): string | null {
  if (mode !== 'shared' || !sharing.available) return null
  const free = freeWholeGb(sharing.booking)
  const gb = typeof value === 'string' && value.trim() !== '' ? Number(value) : value
  if (typeof gb !== 'number' || !Number.isInteger(gb) || gb < MIN_LIMIT_GB) return `GPU memory must be a whole number of GB, ${MIN_LIMIT_GB} or more.`
  return gb > free ? `Only ${free} GB of the card's ${sharing.booking.total_gb} GB is still free to book.` : null
}

/** "N GB of the card's M GB is still free to book. The limit stays booked ..." */
export const gpuMemoryHint = (booking: GpuBooking): string => `${freeWholeGb(booking)} GB of the card's ${booking.total_gb} GB is still free to book. ${SHARED_LIMIT_HINT}`

/** The sentence under the select for the mode that is picked. */
export const gpuCaption = (mode: string | undefined): string => GPU_OPTIONS.find((option) => option.value === (mode ?? 'none'))?.caption ?? ''

/** The lines of the GPU select: "GPU in a container" can be picked only while the offer is a real choice, "Shared partition" only while it is available (else its reason is in brackets). */
export function gpuLines(offer: GpuOffer, sharing: SharedPartition): GpuOption[] {
  return GPU_OPTIONS.map((option) => {
    if (option.value === 'container') return { ...option, disabled: offer.show !== 'choice' }
    if (option.value !== 'shared') return option
    return { ...option, disabled: !sharing.available, label: sharing.available || sharing.reason === null ? option.label : `${option.label} (${sharing.reason})` }
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

/** The mode to send: the GPU only when it was chosen and the offer is still a choice (a changed kind or machine drops it); a shared partition also needs it to be available. */
export function gpuModeToSend(offer: GpuOffer, chosen: string | undefined, sharing: SharedPartition): GpuMode {
  if (offer.show !== 'choice') return 'none'
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
