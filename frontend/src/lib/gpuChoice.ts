// The GPU part of the new-VM form and of a machine's page: what to offer (or say) for a machine and a kind, and how a workload shows that it has the GPU. Pure functions, no DOM, no network.
import type { Machine, Workload } from './types.ts'

export type GpuMode = 'none' | 'container'

/** What the form shows about the GPU. `nothing`: no GPU on that machine (or a Mac), so there is no GPU line at all. */
export type GpuOffer =
  | { show: 'nothing' }
  | { show: 'choice'; card: string }
  | { show: 'vm_text'; text: string }
  | { show: 'needs_toolkit'; text: string }

export const VM_GPU_TEXT = 'A VM cannot use the GPU yet: that needs virtualization turned on in the BIOS (SVM) and the card passed through to one VM.'
export const NEEDS_TOOLKIT_TEXT = 'This machine needs the NVIDIA container toolkit first'
export const NO_GPU_LABEL = 'No GPU'
export const SHARE_GPU_LABEL = "Share the machine's GPU"
export const GPU_EXPLAINED = 'A container shares the machine, so it can use the same GPU as other work on it.'
const NVIDIA = 'nvidia'
const MAC = 'macos'

/** The NVIDIA card a Linux machine reports, or null. Macs never count: Apple's container tool gives no GPU to containers as far as we know. */
export function nvidiaCard(machine: Machine | undefined): string | null {
  if (!machine || machine.os === MAC) return null
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

/** The mode to send: the GPU only when it was chosen and the offer is still a choice (a changed kind or machine drops it). */
export function gpuModeToSend(offer: GpuOffer, chosen: string | undefined): GpuMode {
  return offer.show === 'choice' && chosen === 'container' ? 'container' : 'none'
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
