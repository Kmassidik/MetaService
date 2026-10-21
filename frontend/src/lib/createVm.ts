// What the Create VM form needs to know about the machines: which can take a new VM right now and why not, which kinds each can run, and the form's starting values. Pure functions, no DOM, no network.
import { vmsMachineFromRoute } from './routes.ts'
import type { Machine, WorkloadForm, WorkloadKind } from './types.ts'

/** The form's fields plus the machine it goes to ('' while none is picked). */
export type NewVmForm = WorkloadForm & { machine: string }

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

export interface KindChoice {
  kind: WorkloadKind
  label: string
  disabled: boolean
}

const REASON_OFFLINE = 'offline'
const REASON_NEEDS_SETUP = 'needs setup'
const REASON_BUSY = 'busy'
const REASON_CONTAINERS_ONLY = 'containers only'
const REASON_NOTHING = 'cannot run VMs or containers'
export const DEFAULT_SIZES = { cpu: 2, ramGb: 2, diskGb: 20 }
const MB_PER_GB = 1024

/** The reason this machine cannot take a new VM now, or null. */
function blockingReason(machine: Machine, vm: boolean, container: boolean): string | null {
  if (machine.state === 'offline') return REASON_OFFLINE
  if (machine.problems?.length) return REASON_NEEDS_SETUP
  if (machine.state === 'busy') return REASON_BUSY
  return vm || container ? null : REASON_NOTHING
}

function choiceFor(machine: Machine): MachineChoice {
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
export const machineChoices = (machines: Machine[]): MachineChoice[] => machines.map(choiceFor).sort((left, right) => left.name.localeCompare(right.name, 'en', { sensitivity: 'base' }))

/** The two kinds, with the VM kind switched off (and the reason in its label) on a machine that runs containers only. */
export function kindChoices(choice: MachineChoice | undefined): KindChoice[] {
  const vmAllowed = choice?.vm ?? true
  const containerAllowed = choice?.container ?? true
  return [
    { kind: 'vm', label: vmAllowed ? 'VM' : 'VM (this machine runs containers only)', disabled: !vmAllowed },
    { kind: 'container', label: 'Container', disabled: !containerAllowed },
  ]
}

/** The kind to keep after a machine is picked: the current one when the machine runs it, else the first kind it does run. */
export function kindAfterPick(choice: MachineChoice | undefined, current: string): string {
  const allowed = kindChoices(choice).filter((entry) => !entry.disabled)
  return allowed.some((entry) => entry.kind === current) ? current : (allowed[0]?.kind ?? current)
}

/** The machine named in the address (?machine=<id>) when it is on the list and can take a new VM; otherwise '' (nothing preselected). */
export function preselectedMachine(route: string, choices: MachineChoice[]): string {
  const wanted = vmsMachineFromRoute(route)
  return choices.find((choice) => choice.id === wanted && !choice.disabled)?.id ?? ''
}

/** The sizes a machine was set up to give a new VM; only the ones it has. */
export function machineDefaults(machine: Machine | undefined): Partial<Pick<WorkloadForm, 'cpu' | 'ramGb' | 'diskGb'>> {
  const settings = machine?.settings
  return {
    ...(settings?.vm_cpu ? { cpu: settings.vm_cpu } : {}),
    ...(settings?.vm_ram_mb ? { ramGb: settings.vm_ram_mb / MB_PER_GB } : {}),
    ...(settings?.vm_disk_gb ? { diskGb: settings.vm_disk_gb } : {}),
  }
}

/** A form with nothing typed: the usual sizes, or the ones the machine was set up with, and a kind the machine runs. */
export function blankForm(machine: Machine | undefined): NewVmForm {
  const form: NewVmForm = { name: '', kind: 'vm', ...DEFAULT_SIZES, ...machineDefaults(machine), machine: machine?.id ?? '' }
  return { ...form, kind: kindAfterPick(machine ? choiceFor(machine) : undefined, form.kind) }
}
