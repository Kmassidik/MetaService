// What one machine card says about the machine, as a list of label and value rows: the address, the profile its person saved, and what the machine
// is made of. Every card has the same rows in the same order; a fact the machine does not report keeps its row and shows a dash, so a gap is never
// a missing row and the values line up down a column of cards. Pure: no DOM, no network, plain text only.
import { cpuModelText } from './cpuModel.ts'
import { archName, osName, profileLabel } from './format.ts'
import { gpuName } from './hardware.ts'
import type { Machine } from './types.ts'

/** The one mark a row shows where a fact is missing. The same in every row of the card. */
export const UNKNOWN = '—'
/** The value of a machine that has no VMs. */
export const NO_VMS = 'No VMs'
const SEPARATOR = ' · '
/** The panel's own placeholder for a value it does not have, which reads as the card's dash here. */
const PANEL_PLACEHOLDER = '–'

/** Which fact a row holds, so the card can give a row its own icon and its own hook. */
export type FactKey = 'address' | 'type' | 'os' | 'cores' | 'cpu' | 'gpu' | 'vms'

/** One row of the card's fact list: the word it is filed under, and the one line that answers it. */
export interface CardFact {
  key: FactKey
  label: string
  value: string
}

/** The card's dash for a text the panel does not know: its own placeholder becomes the card's. */
const dashed = (text: string): string => (text === PANEL_PLACEHOLDER ? UNKNOWN : text)

/** "Apple Silicon" for a Mac on Apple's own chips; otherwise the architecture in short: "ARM", "x86". */
export function chipName(machine: Machine): string {
  return dashed(machine.os === 'macos' && machine.arch === 'arm64' ? 'Apple Silicon' : archName(machine.arch))
}

/** "macOS · Apple Silicon", or the one of the two the machine does report, or the dash when it reports neither. */
function osValue(machine: Machine): string {
  const known = [dashed(osName(machine.os)), chipName(machine)].filter((part) => part !== UNKNOWN)
  return known.length === 0 ? UNKNOWN : known.join(SEPARATOR)
}

/** "14" for a machine with 14 cores: the label says the unit, so the value is the number alone. */
function coresValue(machine: Machine): string {
  const cores = machine.cpu_cores
  return typeof cores === 'number' && Number.isInteger(cores) && cores >= 1 ? String(cores) : UNKNOWN
}

/** "NVIDIA GeForce RTX 5090", the cards of a machine that has more than one, or the dash. */
function gpuValue(machine: Machine): string {
  const gpus = machine.gpu.map(gpuName).join(', ')
  return gpus === '' ? UNKNOWN : gpus
}

/** "No VMs", "1 VM", "3 VMs": how many VMs the machine has, as its row and its header chip say it. */
export function vmsChip(count: number): string {
  if (count < 1) return NO_VMS
  return count === 1 ? '1 VM' : `${count} VMs`
}

/** The card's facts, in the one order every card uses. A row is always here; only its value may be the dash. */
export function cardFacts(machine: Machine): CardFact[] {
  return [
    { key: 'address', label: 'ADDRESS', value: machine.ip || UNKNOWN },
    { key: 'type', label: 'TYPE', value: profileLabel(machine.settings?.profile) },
    { key: 'os', label: 'OS', value: osValue(machine) },
    { key: 'cores', label: 'CORES', value: coresValue(machine) },
    { key: 'cpu', label: 'CPU', value: cpuModelText(machine.cpu_model) ?? UNKNOWN },
    { key: 'gpu', label: 'GPU', value: gpuValue(machine) },
    { key: 'vms', label: 'VMS', value: vmsChip(machine.workloads.length) },
  ]
}
