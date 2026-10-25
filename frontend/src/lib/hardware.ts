// What a machine is made of, as the panel shows it: the computer's make and model, each kind of CPU core, the drives, and the GPU's details.
// The parent already checks and cleans all of it; this reads it again defensively, so an odd value is left out rather than shown. Pure functions,
// no DOM, no network. Every result is plain text, only ever put in as text.
import { cpuModelText } from './cpuModel.ts'
import { formatMb } from './format.ts'
import type { Gpu, Machine } from './types.ts'

export interface CoreType {
  name: string
  /** Physical cores of this kind, threads not counted. */
  cores: number
  max_mhz?: number
}

export interface Drive {
  model: string
  /** Decimal GB, as drives are sold. */
  size_gb: number
  kind: DriveKind
}

export type DriveKind = 'nvme' | 'ssd' | 'hdd'

/** `hardware` on a machine: every part is optional, and a helper that says none of it gives null. */
export interface Hardware {
  system?: string
  core_types: CoreType[]
  disks: Drive[]
}

export const USES_MACHINE_MEMORY = "uses the machine's memory"
export const SHARED_WITH_GPU = 'shared with the GPU'
const DRIVE_KINDS: Record<DriveKind, string> = { nvme: 'NVMe', ssd: 'SSD', hdd: 'HDD' }
const MAX_ITEMS = 8
const MAX_MHZ = 20_000
const MHZ_PER_GHZ = 1000
const GB_PER_TB = 1000

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)
const wholeIn = (value: unknown, low: number, high: number): value is number => typeof value === 'number' && Number.isInteger(value) && value >= low && value <= high
const textOf = (value: unknown): string | null => (typeof value === 'string' ? cpuModelText(value) : null)
const listOf = (value: unknown): unknown[] => (Array.isArray(value) ? value.slice(0, MAX_ITEMS) : [])

function coreType(value: unknown): CoreType | null {
  if (!isRecord(value)) return null
  const name = textOf(value.name)
  if (name === null || !wholeIn(value.cores, 1, 100_000)) return null
  return wholeIn(value.max_mhz, 1, MAX_MHZ) ? { name, cores: value.cores, max_mhz: value.max_mhz } : { name, cores: value.cores }
}

function drive(value: unknown): Drive | null {
  if (!isRecord(value)) return null
  const model = textOf(value.model)
  const kind = value.kind
  if (model === null || !wholeIn(value.size_gb, 1, 100_000_000) || (kind !== 'nvme' && kind !== 'ssd' && kind !== 'hdd')) return null
  return { model, size_gb: value.size_gb, kind }
}

/** The machine's `hardware`, with anything out of shape left out; null when there is nothing to show. */
export function readHardware(value: unknown): Hardware | null {
  if (!isRecord(value)) return null
  const system = textOf(value.system)
  const core_types = listOf(value.core_types).map(coreType).filter((item): item is CoreType => item !== null)
  const disks = listOf(value.disks).map(drive).filter((item): item is Drive => item !== null)
  if (system === null && core_types.length === 0 && disks.length === 0) return null
  return system === null ? { core_types, disks } : { system, core_types, disks }
}

/** 3900 → "3.9 GHz". */
export function ghz(mhz: number): string {
  return `${(mhz / MHZ_PER_GHZ).toFixed(1)} GHz`
}

/** A drive's size as it is sold: "4.1 TB", "10 TB", "512 GB". */
export function driveSize(gb: number): string {
  return gb >= GB_PER_TB ? `${(gb / GB_PER_TB).toFixed(1).replace(/\.0$/, '')} TB` : `${gb} GB`
}

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? '' : 's'}`
const upTo = (mhz: number | undefined) => (mhz === undefined ? '' : ` up to ${ghz(mhz)}`)

/**
 * The CPU row. Several kinds of core: "10× Cortex-X925 up to 3.9 GHz + 10× Cortex-A725 up to 2.8 GHz · 20 cores". One kind: the name, its cores, the threads
 * when there are more, and its top clock: "AMD Ryzen 9 5950X 16-Core Processor · 16 cores, 32 threads · up to 5.1 GHz". No kinds: the name and the count, as before.
 */
export function cpuText(machine: Machine): string {
  const name = cpuModelText(machine.cpu_model)
  const threads = machine.cpu_cores ?? null
  const kinds = readHardware(machine.hardware)?.core_types ?? []
  if (kinds.length > 1) {
    const total = kinds.reduce((sum, kind) => sum + kind.cores, 0)
    return `${kinds.map((kind) => `${kind.cores}× ${kind.name}${upTo(kind.max_mhz)}`).join(' + ')} · ${plural(total, 'core')}`
  }
  const [only] = kinds
  if (only) {
    const extraThreads = threads !== null && threads > only.cores ? `, ${plural(threads, 'thread')}` : ''
    const clock = only.max_mhz === undefined ? '' : ` · up to ${ghz(only.max_mhz)}`
    return `${name ?? only.name} · ${plural(only.cores, 'core')}${extraThreads}${clock}`
  }
  const cores = `${threads ?? '–'} cores`
  return name === null ? cores : `${name} · ${cores}`
}

/** "SAMSUNG MZALC4T0HBL1-00B07 · 4.1 TB NVMe", one per drive; null when the machine does not say its drives. */
export function drivesText(hardware: Hardware | null): string | null {
  if (!hardware || hardware.disks.length === 0) return null
  return hardware.disks.map((disk) => `${disk.model} · ${driveSize(disk.size_gb)} ${DRIVE_KINDS[disk.kind]}`).join(', ')
}

/** A GPU's name, with its maker in front only when the name does not already say it: "NVIDIA GB10", not "nvidia NVIDIA GB10". */
export function gpuName(gpu: Gpu): string {
  const model = gpu.model.trim()
  return model.toLowerCase().includes(gpu.vendor.trim().toLowerCase()) ? model : `${gpu.vendor} ${model}`.trim()
}

/** Its own memory ("32 GB"), or that it works in the machine's memory; null when neither is known. */
function gpuMemory(gpu: Gpu): string | null {
  if (wholeIn(gpu.memory_mb, 1, 100_000_000)) return formatMb(gpu.memory_mb)
  return gpu.uses_system_memory === true ? USES_MACHINE_MEMORY : null
}

const known = (parts: (string | null | undefined | false)[]): string[] => parts.filter((part): part is string => typeof part === 'string' && part !== '')

/** "NVIDIA GB10 · Blackwell · uses the machine's memory": the name, family and memory, for the line under the Create VM GPU field. */
export function gpuShortText(gpu: Gpu): string {
  return known([gpuName(gpu), textOf(gpu.architecture), gpuMemory(gpu)]).join(' · ')
}

/** Everything the helper said about a GPU: "NVIDIA GB10 · Blackwell · uses the machine's memory · compute 12.1 · up to 3,003 MHz · driver 580.173.02". */
export function gpuDetailText(gpu: Gpu): string {
  const capability = textOf(gpu.compute_capability)
  const driver = textOf(gpu.driver_version)
  const clock = wholeIn(gpu.max_clock_mhz, 1, MAX_MHZ) ? `up to ${gpu.max_clock_mhz.toLocaleString('en-US')} MHz` : null
  return known([gpuShortText(gpu), capability && `compute ${capability}`, clock, driver && `driver ${driver}`]).join(' · ')
}

/** True when a GPU of this machine works in the machine's memory, so its memory is shared with the GPU. */
export const memorySharedWithGpu = (machine: Machine): boolean => machine.gpu.some((gpu) => gpu.uses_system_memory === true)
