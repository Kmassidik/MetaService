// What the Create VM window needs to know about the machines: which can take a new VM right now and why not, which kinds each can run, and the form's starting values. Pure functions, no DOM, no network.
import { STOCK_IMAGE } from './images.ts'
import { vmsMachineFromRoute } from './routes.ts'
import type { Machine, WorkloadForm, WorkloadKind } from './types.ts'
import { initialSize, MEDIUM_SIZE, type SizeDefaults, type SizeKey } from './vmSize.ts'

/** The form's fields plus the machine it goes to ('' while none is picked) and the size card that is picked. */
export type NewVmForm = WorkloadForm & { machine: string; size: SizeKey }

export interface MachineChoice {
  id: string
  name: string
  /** What the dropdown shows: the name, and the reason in brackets when there is one. */
  label: string
  /** True when no new VM can be made on this machine right now. */
  disabled: boolean
  /** Why the machine is disabled or limited, in plain words; null when it is ready for anything. */
  reason: string | null
  /** The first problem the machine reported, to explain "needs setup" under the dropdown. */
  detail: string | null
  vm: boolean
  container: boolean
}

/** One of the two Runtime cards. */
export interface RuntimeCard {
  kind: WorkloadKind
  label: string
  caption: string
  disabled: boolean
  /** Why the card is greyed out; null when it can be picked. */
  reason: string | null
}

const REASON_OFFLINE = 'offline'
const REASON_NEEDS_SETUP = 'needs setup'
const REASON_BUSY = 'busy'
const REASON_CONTAINERS_ONLY = 'containers only'
const REASON_NOTHING = 'cannot run VMs or containers'
const REASON_NO_VM = 'This machine runs containers only'
const REASON_NO_CONTAINER = 'This machine cannot run containers'
const MB_PER_GB = 1024

/** The reason this machine cannot take a new VM now, or null. */
function blockingReason(machine: Machine, vm: boolean, container: boolean): string | null {
  if (machine.state === 'offline') return REASON_OFFLINE
  if (machine.problems?.length) return REASON_NEEDS_SETUP
  if (machine.state === 'busy') return REASON_BUSY
  return vm || container ? null : REASON_NOTHING
}

export function machineChoice(machine: Machine): MachineChoice {
  // A machine that has not reported what it can run is not guessed about: the parent refuses what does not fit.
  const vm = machine.capabilities?.vm ?? true
  const container = machine.capabilities?.container ?? true
  const blocking = blockingReason(machine, vm, container)
  const reason = blocking ?? (vm ? null : REASON_CONTAINERS_ONLY)
  return {
    id: machine.id,
    name: machine.name,
    label: reason ? `${machine.name} (${reason})` : machine.name,
    disabled: blocking !== null,
    reason,
    detail: machine.problems?.[0]?.message ?? null,
    vm,
    container,
  }
}

/** Every machine on the list, sorted by name, each with whether it can be picked and why not. */
export const machineChoices = (machines: Machine[]): MachineChoice[] => machines.map(machineChoice).sort((left, right) => left.name.localeCompare(right.name, 'en', { sensitivity: 'base' }))

/** One line for each machine that cannot be picked: its name, why, and what the machine itself said about it. */
export function unavailableNotes(choices: MachineChoice[]): string[] {
  return choices.filter((choice) => choice.disabled).map((choice) => `${choice.name}: ${choice.reason}${choice.detail ? ` (${choice.detail})` : ''}`)
}

/** The two Runtime cards, Container first; one is greyed out with its reason on a machine that cannot run it. */
export function runtimeCards(choice: MachineChoice | undefined): RuntimeCard[] {
  const vmAllowed = choice?.vm ?? true
  const containerAllowed = choice?.container ?? true
  return [
    { kind: 'container', label: 'Container', caption: 'fast stop & wake', disabled: !containerAllowed, reason: containerAllowed ? null : REASON_NO_CONTAINER },
    { kind: 'vm', label: 'VM', caption: 'full VM · classic', disabled: !vmAllowed, reason: vmAllowed ? null : REASON_NO_VM },
  ]
}

/** The kind to keep after a machine is picked: the current one when the machine runs it, else the first kind it does run. */
export function kindAfterPick(choice: MachineChoice | undefined, current: string): string {
  const allowed = runtimeCards(choice).filter((entry) => !entry.disabled)
  return allowed.some((entry) => entry.kind === current) ? current : (allowed[0]?.kind ?? current)
}

/** The machine named in the address (?machine=<id>) when it is on the list and can take a new VM; otherwise '' (nothing preselected). */
export function preselectedMachine(route: string, choices: MachineChoice[]): string {
  const wanted = vmsMachineFromRoute(route)
  return choices.find((choice) => choice.id === wanted && !choice.disabled)?.id ?? ''
}

/** The machines the dropdown lists: every one, or only the one the window was opened from (on that machine's own page). */
export const machineOptions = (choices: MachineChoice[], only: string | null): MachineChoice[] => (only === null ? choices : choices.filter((choice) => choice.id === only))

/** The machine the window starts with chosen: the one it was opened from, else the pickable one named in the address, else the only one that can take a VM, else none (''). */
export function startingMachine(route: string, only: string | null, choices: MachineChoice[]): string {
  const pickable = choices.filter((choice) => !choice.disabled)
  const alone = pickable.length === 1 ? (pickable[0]?.id ?? '') : ''
  return only ?? (preselectedMachine(route, choices) || alone)
}

/** The sizes a machine was set up to give a new VM; only the ones it has. */
export function machineDefaults(machine: Machine | undefined): SizeDefaults {
  const settings = machine?.settings
  return {
    ...(settings?.vm_cpu ? { cpu: settings.vm_cpu } : {}),
    ...(settings?.vm_ram_mb ? { ramGb: settings.vm_ram_mb / MB_PER_GB } : {}),
    ...(settings?.vm_disk_gb ? { diskGb: settings.vm_disk_gb } : {}),
  }
}

/** The form after a machine is picked: its size card and numbers (what the machine gives a new VM, Medium without any) and a kind it runs. The name and image are kept. */
export function pickMachine(form: NewVmForm, machine: Machine | undefined): NewVmForm {
  const { key, ...sizes } = initialSize(machine, machineDefaults(machine))
  return { ...form, ...sizes, size: key, machine: machine?.id ?? '', kind: kindAfterPick(machine ? machineChoice(machine) : undefined, form.kind) }
}

/** A form with nothing typed, as it is when a machine (or none) is picked. */
export const blankForm = (machine: Machine | undefined): NewVmForm =>
  pickMachine({ name: '', kind: 'vm', cpu: MEDIUM_SIZE.cpu, ramGb: MEDIUM_SIZE.ramGb, diskGb: MEDIUM_SIZE.diskGb, size: MEDIUM_SIZE.key, machine: '', bundle: STOCK_IMAGE }, machine)
