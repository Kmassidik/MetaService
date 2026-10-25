// The CPU part of the new-VM form, as in Proxmox's Processors window: what a machine lets a VM set (sockets, the CPU model, extra flags) and a container (a CPU limit),
// the sentence the window shows when it cannot, what is left of the choices after another machine is picked, and what goes in the order. Pure functions, no DOM, no network.
import { MAC_OS } from './gpuChoice.ts'
import type { CpuFlagId, FormNumber, Machine, WorkloadForm } from './types.ts'

export const HOST_MODEL = 'host'
export const MAX_SOCKETS = 8
export const MIN_LIMIT_CORES = 0.1
const PERCENT_PER_CORE = 100

/** What a flag's three buttons say: Default leaves it to the CPU model. */
export type FlagSetting = 'off' | 'default' | 'on'
export const FLAG_SETTINGS: readonly FlagSetting[] = ['off', 'default', 'on']

export interface CpuFlag {
  id: CpuFlagId
  /** What the flag does, for the Description column. */
  description: string
}

/** The flags the table lists, in its order. */
export const CPU_FLAGS: readonly CpuFlag[] = [
  { id: 'nested-virt', description: 'Lets the VM run VMs of its own: svm on an AMD machine, vmx on an Intel one. Off takes both away.' },
  { id: 'aes', description: 'AES instructions in the CPU, for fast encryption of disks, TLS and VPNs.' },
]

export const HOST_VENDOR = 'This machine'
const AMD_MODELS = /^(EPYC|Opteron|phenom|athlon)/i
const INTEL_MODELS = /^(Skylake|Cascadelake|Cooperlake|Icelake|SapphireRapids|GraniteRapids|SierraForest|Broadwell|Haswell|IvyBridge|SandyBridge|Westmere|Nehalem|Penryn|Conroe|KnightsMill|Snowridge|Denverton|core2duo|coreduo|pentium)/i
const GENERIC_MODELS = /^(kvm|qemu)(32|64)$/

export const MAC_CPU_NOTE = "On a Mac a VM always gets the Mac's own CPU on one socket."
export const ARM_CPU_NOTE = "On an Arm machine a VM always gets the machine's own CPU: the CPU types and extra flags are for x86 machines, so a newer helper does not add them."
const ARM_ARCHES = ['aarch64', 'arm64']
export const OLD_HELPER_CPU_NOTE = "This machine's helper cannot set sockets, the CPU type or CPU flags, so a VM gets the machine's own CPU on one socket. Update the helper to choose them."
export const MAC_LIMIT_NOTE = "On a Mac a container's CPU time cannot be capped: it gets its cores."
export const OLD_HELPER_LIMIT_NOTE = "This machine's helper cannot cap a container's CPU time. Update the helper to set a limit."
export const SOCKETS_TEXT = `Sockets must be a whole number from 1 to ${MAX_SOCKETS}.`
export const ONE_SOCKET_TEXT = 'This machine gives a VM one socket.'
export const WHOLE_CORES_TEXT = 'Cores must be a whole number.'

/** What one machine lets a new VM or container set about its CPU. A machine that does not say offers the host CPU on one socket, as every VM had before. */
export interface CpuOffer {
  /** The CPU models a VM can be given, host first. */
  models: string[]
  /** More than one socket. */
  sockets: boolean
  /** The flags a VM can have switched on or off, in the table's order. */
  flags: CpuFlagId[]
  /** A hard cap on a container's CPU time. */
  limit: boolean
}

export function cpuOffer(machine: Machine | undefined): CpuOffer {
  const capabilities = machine?.capabilities
  const others = (capabilities?.cpu_models ?? []).filter((model) => model !== HOST_MODEL)
  return {
    models: [HOST_MODEL, ...others],
    sockets: capabilities?.cpu_topology === true,
    flags: CPU_FLAGS.map((flag) => flag.id).filter((id) => capabilities?.cpu_flags?.includes(id) === true),
    limit: capabilities?.cpu_limit === true,
  }
}

/** The Vendor column of the CPU type list: AMD, Intel, Generic for kvm64 and qemu64, and "This machine" for host. */
export function modelVendor(model: string): string {
  if (model === HOST_MODEL) return HOST_VENDOR
  if (AMD_MODELS.test(model)) return 'AMD'
  if (INTEL_MODELS.test(model)) return 'Intel'
  return GENERIC_MODELS.test(model) ? 'Generic' : 'Other'
}

/** The plain sentence under the CPU fields when the machine offers none of this kind's choices; null when it offers one, or no machine is picked. */
export function cpuNote(machine: Machine | undefined, kind: string, offer: CpuOffer): string | null {
  if (!machine) return null
  const mac = machine.os === MAC_OS
  if (kind === 'container') return offer.limit ? null : mac ? MAC_LIMIT_NOTE : OLD_HELPER_LIMIT_NOTE
  if (offer.sockets || offer.models.length > 1 || offer.flags.length > 0) return null
  if (mac) return MAC_CPU_NOTE
  return ARM_ARCHES.includes(machine.arch) ? ARM_CPU_NOTE : OLD_HELPER_CPU_NOTE
}

/** True for a box with nothing in it. */
const empty = (value: FormNumber): boolean => value === undefined || value === null || String(value).trim() === ''

/** The sockets the form asks for, read as a number (1 when the box was never touched). */
const socketsAsked = (form: WorkloadForm): number => Number(form.cpuSockets ?? 1)

/** Cores per socket, as the Cores box shows it: the total divided by the sockets, or the total as typed while either is not a usable number. */
export function coresPerSocket(form: WorkloadForm): FormNumber {
  const sockets = socketsAsked(form)
  const total = Number(form.cpu)
  if (empty(form.cpu) || !Number.isFinite(total) || !Number.isInteger(sockets) || sockets < 1) return form.cpu
  return total / sockets
}

/** The total after the Cores box changed: the cores times the sockets, or the text as typed while it is not a number (the form then says what is wrong). */
export function totalFromCores(cores: string, form: WorkloadForm): FormNumber {
  const sockets = socketsAsked(form)
  if (empty(cores) || !Number.isFinite(Number(cores)) || !Number.isInteger(sockets) || sockets < 1) return cores
  return Number(cores) * sockets
}

/** The total after the Sockets box changed: the cores per socket stay and the total follows; it stays as it was while the sockets are not a usable number. */
export function totalFromSockets(sockets: string, form: WorkloadForm): FormNumber {
  const cores = Number(coresPerSocket(form))
  const count = Number(sockets)
  if (empty(sockets) || !Number.isInteger(count) || count < 1 || !Number.isFinite(cores)) return form.cpu
  return cores * count
}

/** The limit in percent of one core (1.5 cores is 150), or null when no limit is typed. */
export function limitPercent(cores: FormNumber): number | null {
  if (empty(cores)) return null
  const value = Number(cores)
  return Number.isFinite(value) ? Math.round(value * PERCENT_PER_CORE) : null
}

function limitProblem(form: WorkloadForm, offer: CpuOffer): string | null {
  if (empty(form.cpuLimit)) return null
  if (!offer.limit) return OLD_HELPER_LIMIT_NOTE
  const most = Number(form.cpu)
  const cores = Number(form.cpuLimit)
  const ceiling = Number.isFinite(most) && most >= 1 ? most : 1
  return Number.isFinite(cores) && cores >= MIN_LIMIT_CORES && cores <= ceiling ? null : `CPU limit must be between ${MIN_LIMIT_CORES} and ${ceiling} cores, or empty for no limit.`
}

/** Why the CPU choices cannot be sent as they are, in plain words; null when they can. Only the picked kind's fields count. */
export function cpuProblem(form: WorkloadForm, offer: CpuOffer): string | null {
  if (form.kind === 'container') return limitProblem(form, offer)
  if (form.kind !== 'vm') return null
  const sockets = socketsAsked(form)
  if (!Number.isInteger(sockets) || sockets < 1 || sockets > MAX_SOCKETS) return SOCKETS_TEXT
  if (sockets > 1 && !offer.sockets) return ONE_SOCKET_TEXT
  const total = Number(form.cpu)
  if (Number.isFinite(total) && !Number.isInteger(total / sockets)) return WHOLE_CORES_TEXT
  if (form.cpuType !== undefined && !offer.models.includes(form.cpuType)) return `This machine cannot give a VM the ${form.cpuType} CPU.`
  const unoffered = Object.keys(form.cpuFlags ?? {}).find((flag) => !offer.flags.some((id) => id === flag))
  return unoffered === undefined ? null : `This machine cannot switch the ${unoffered} flag.`
}

/** The CPU keys of the order: only what differs from before (2 sockets or more, a type other than host, the flags set, a limit), and only for the kind they belong to. */
export function cpuFields(form: WorkloadForm): Record<string, unknown> {
  if (form.kind === 'container') {
    const percent = limitPercent(form.cpuLimit)
    return percent === null ? {} : { cpu_limit_percent: percent }
  }
  if (form.kind !== 'vm') return {}
  const sockets = socketsAsked(form)
  const flags = Object.fromEntries(Object.entries(form.cpuFlags ?? {}).filter(([, setting]) => setting === 'on' || setting === 'off'))
  return {
    ...(sockets >= 2 ? { cpu_sockets: sockets } : {}),
    ...(form.cpuType !== undefined && form.cpuType !== HOST_MODEL ? { cpu_type: form.cpuType } : {}),
    ...(Object.keys(flags).length > 0 ? { cpu_flags: flags } : {}),
  }
}

/** What is left of the CPU choices after another machine is picked: what it does not offer goes back to the default, and the total keeps its cores. */
export function cpuAfterChange(form: WorkloadForm, offer: CpuOffer): Pick<WorkloadForm, 'cpuSockets' | 'cpuType' | 'cpuFlags' | 'cpuLimit'> {
  const flags = Object.fromEntries(Object.entries(form.cpuFlags ?? {}).filter(([flag]) => offer.flags.some((id) => id === flag)))
  return {
    cpuSockets: offer.sockets ? form.cpuSockets : undefined,
    cpuType: form.cpuType !== undefined && offer.models.includes(form.cpuType) ? form.cpuType : undefined,
    cpuFlags: Object.keys(flags).length > 0 ? flags : undefined,
    cpuLimit: offer.limit ? form.cpuLimit : undefined,
  }
}

/** The button of a flag that is lit: Default while the form does not name it. */
export const flagSetting = (form: WorkloadForm, flag: CpuFlagId): FlagSetting => form.cpuFlags?.[flag] ?? 'default'

/** The flags after one button was pressed: Default takes the flag out of the order. */
export function withFlag(flags: WorkloadForm['cpuFlags'], flag: CpuFlagId, setting: FlagSetting): WorkloadForm['cpuFlags'] {
  const next = { ...flags }
  if (setting === 'default') delete next[flag]
  else next[flag] = setting
  return Object.keys(next).length > 0 ? next : undefined
}

/** The machines whose helper can switch this flag, by name, for the Supported on column. */
export const flagMachines = (machines: Machine[], flag: CpuFlagId): string[] =>
  machines.filter((machine) => machine.capabilities?.cpu_flags?.includes(flag) === true).map((machine) => machine.name).sort((left, right) => left.localeCompare(right, 'en', { sensitivity: 'base' }))
