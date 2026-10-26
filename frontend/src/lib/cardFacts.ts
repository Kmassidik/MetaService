// What one machine card says, built from the machine's own facts: the single hardware line under the address, the address line itself, and the
// header chip that says how many VMs the machine has. Every card has the same rows; a fact the machine does not report keeps its place as a dash,
// so a gap is never a missing row. Pure: no DOM, no network, plain text only.
import { cpuModelText } from './cpuModel.ts'
import { archName, osName, profileLabel } from './format.ts'
import { gpuName, readHardware } from './hardware.ts'
import type { Machine } from './types.ts'

/** The one mark a row shows where a fact is missing. The same in every row of the card. */
export const UNKNOWN = '—'
/** The header chip of a machine that has no VMs. */
export const NO_VMS = 'No VMs'
const SEPARATOR = ' · '
const ONE_CORE = '1 core'
/** The panel's own placeholder for a value it does not have, which reads as the card's dash here. */
const PANEL_PLACEHOLDER = '–'

/** Which fact a part of the hardware line came from, so the card can keep a part's own hook. */
export type HardwareKind = 'os' | 'chip' | 'cores' | 'gpu' | 'cpu' | 'board'

/** One part of the hardware line, and where it came from. */
export interface HardwarePart {
  kind: HardwareKind
  text: string
}

/** The card's dash for a text the panel does not know: its own placeholder becomes the card's. */
const dashed = (text: string): string => (text === PANEL_PLACEHOLDER ? UNKNOWN : text)

/** "Apple Silicon" for a Mac on Apple's own chips; otherwise the architecture in short: "ARM", "x86". */
export function chipName(machine: Machine): string {
  return dashed(machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch))
}

/** "14 cores", "1 core", or the dash. */
function coresText(machine: Machine): string {
  const cores = machine.cpu_cores
  if (typeof cores !== 'number' || !Number.isInteger(cores) || cores < 1) return UNKNOWN
  return cores === 1 ? ONE_CORE : `${cores} cores`
}

/**
 * The one name that says what the machine is, and where it came from: its GPU ("NVIDIA GB10"), else its CPU's name ("Apple M4 Max"), else the
 * computer's own model ("Mac mini"). A GPU names a machine best on a fleet where most of them are chosen for their card, and its name carries the
 * main chip of a machine like a DGX Spark.
 */
function namePart(machine: Machine): HardwarePart {
  const gpu = machine.gpu.map(gpuName).join(', ')
  if (gpu !== '') return { kind: 'gpu', text: gpu }
  const cpu = cpuModelText(machine.cpu_model)
  if (cpu !== null) return { kind: 'cpu', text: cpu }
  return { kind: 'board', text: readHardware(machine.hardware)?.system ?? UNKNOWN }
}

/** The parts of the card's one hardware line, in order: the system, the chip, the cores, and the machine's own name. */
export function hardwareParts(machine: Machine): HardwarePart[] {
  return [
    { kind: 'os', text: dashed(osName(machine.os)) },
    { kind: 'chip', text: chipName(machine) },
    { kind: 'cores', text: coresText(machine) },
    namePart(machine),
  ]
}

/**
 * The card's one hardware line: "macOS · Apple Silicon · 14 cores · Apple M4 Max", "Linux · ARM · 20 cores · NVIDIA GB10". A machine that says
 * nothing about itself gets the single dash. The line is cut with an ellipsis on the card; its `title` holds all of it.
 */
export function hardwareLine(machine: Machine): string {
  const parts = hardwareParts(machine).map((part) => part.text)
  return parts.every((text) => text === UNKNOWN) ? UNKNOWN : parts.join(SEPARATOR)
}

/** "192.168.0.40 · Custom": the machine's address and the profile the person saved for it, in the one line under its name. */
export function addressLine(machine: Machine): string {
  return `${machine.ip || UNKNOWN}${SEPARATOR}${profileLabel(machine.settings?.profile)}`
}

/** "No VMs", "1 VM", "3 VMs": the header chip beside the state badge. */
export function vmsChip(count: number): string {
  if (count < 1) return NO_VMS
  return count === 1 ? '1 VM' : `${count} VMs`
}
