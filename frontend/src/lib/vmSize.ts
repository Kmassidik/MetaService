// The size cards of the Create VM window: the three presets, which of them fit a machine and why not, and which card the window starts on.
// Pure functions, no DOM, no network. The machine still checks its own space again when the order arrives; this only greys out what can already be seen not to fit.
import { formatGb, formatMb } from './format.ts'
import type { Machine } from './types.ts'

const MB_PER_GB = 1024

export type PresetKey = 'small' | 'medium' | 'large'
export type SizeKey = PresetKey | 'custom'

export interface VmSize {
  cpu: number
  ramGb: number
  diskGb: number
}

export interface SizePreset extends VmSize {
  key: PresetKey
  label: string
}

export const MEDIUM_SIZE: SizePreset = { key: 'medium', label: 'Medium', cpu: 2, ramGb: 4, diskGb: 40 }

export const SIZE_PRESETS: readonly SizePreset[] = [
  { key: 'small', label: 'Small', cpu: 1, ramGb: 2, diskGb: 20 },
  MEDIUM_SIZE,
  { key: 'large', label: 'Large', cpu: 4, ramGb: 8, diskGb: 60 },
]

export const CUSTOM_LABEL = 'Custom'
export const CUSTOM_CAPTION = 'your specs'

export interface SizeCard {
  key: SizeKey
  label: string
  caption: string
  disabled: boolean
  /** Why the card is greyed out; null when it can be picked. */
  reason: string | null
}

/** "1 · 2GB · 20GB": the caption under a preset. */
export const presetCaption = (size: VmSize): string => `${size.cpu} · ${size.ramGb}GB · ${size.diskGb}GB`

/** Why this size does not fit the machine, in plain words; null when it fits or the machine has not said how much it has (the machine itself then decides). */
export function sizeProblem(size: VmSize, machine: Machine | undefined): string | null {
  if (!machine) return null
  const cores = machine.cpu_cores
  if (typeof cores === 'number' && size.cpu > cores) return `This machine has ${cores} ${cores === 1 ? 'CPU' : 'CPUs'}`
  const freeRam = machine.free_ram_mb
  if (typeof freeRam === 'number' && size.ramGb * MB_PER_GB > freeRam) return `This machine has ${formatMb(freeRam)} free`
  const freeDisk = machine.free_disk_gb
  if (typeof freeDisk === 'number' && size.diskGb > freeDisk) return `This machine has ${formatGb(freeDisk)} disk free`
  return null
}

/** The four cards for one machine: each preset with whether it fits, then Custom (always open: its numbers keep the usual limits). */
export function sizeCards(machine: Machine | undefined): SizeCard[] {
  const presets = SIZE_PRESETS.map((preset): SizeCard => {
    const reason = sizeProblem(preset, machine)
    return { key: preset.key, label: preset.label, caption: presetCaption(preset), disabled: reason !== null, reason }
  })
  return [...presets, { key: 'custom', label: CUSTOM_LABEL, caption: CUSTOM_CAPTION, disabled: false, reason: null }]
}

const sameSize = (left: VmSize, right: VmSize): boolean => left.cpu === right.cpu && left.ramGb === right.ramGb && left.diskGb === right.diskGb

/** The size line that matches numbers typed in the boxes: the preset with exactly these numbers, else Custom. */
export function matchingSize(cpu: unknown, ramGb: unknown, diskGb: unknown): SizeKey {
  const typed: VmSize = { cpu: Number(cpu), ramGb: Number(ramGb), diskGb: Number(diskGb) }
  return SIZE_PRESETS.find((preset) => sameSize(preset, typed))?.key ?? 'custom'
}

/** What "A new VM gets" on a machine's Environment tab holds, only the parts it has. */
export type SizeDefaults = Partial<VmSize>

export type StartingSize = VmSize & { key: SizeKey }

const asStart = (preset: SizePreset): StartingSize => ({ key: preset.key, cpu: preset.cpu, ramGb: preset.ramGb, diskGb: preset.diskGb })

/**
 * The card the window starts on and the numbers behind it.
 * Defaults that equal a preset select that preset; other defaults select Custom filled with them;
 * with none, Medium (or the first preset that fits, or Custom filled like Medium when nothing fits).
 */
export function initialSize(machine: Machine | undefined, defaults: SizeDefaults): StartingSize {
  const wanted: VmSize = { cpu: defaults.cpu ?? MEDIUM_SIZE.cpu, ramGb: defaults.ramGb ?? MEDIUM_SIZE.ramGb, diskGb: defaults.diskGb ?? MEDIUM_SIZE.diskGb }
  if (Object.keys(defaults).length > 0) {
    const preset = SIZE_PRESETS.find((entry) => sameSize(entry, wanted))
    return preset ? asStart(preset) : { key: 'custom', ...wanted }
  }
  const fitting = SIZE_PRESETS.find((entry) => sizeProblem(entry, machine) === null)
  const start = sizeProblem(MEDIUM_SIZE, machine) === null ? MEDIUM_SIZE : fitting
  return start ? asStart(start) : { key: 'custom', ...wanted }
}
