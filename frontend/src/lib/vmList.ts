// What the All VMs page shows: every VM of every machine as one row, narrowed to one machine, sorted, with a count. Pure functions, no DOM, no network.
import { hasGpu } from './gpuChoice.ts'
import { vmsMachineFromRoute } from './routes.ts'
import { isPlainMode, readStoppedReason, reasonNote, type StopNote } from './stoppedReason.ts'
import type { Machine, MachineState, WorkloadKind } from './types.ts'

export interface VmRow {
  machineId: string
  machineName: string
  machineState: MachineState
  machineOs: string
  id: string
  name: string
  kind: WorkloadKind
  state: string
  cpu: number
  ramMb: number
  diskGb: number
  /** True when it was given the machine's GPU. */
  gpu: boolean
  /** Why it stopped, when it stopped by itself and the machine said why. */
  note: StopNote | null
  /** True when it runs without systemd. */
  plain: boolean
}

const IN_PROGRESS = new Set(['creating', 'starting', 'provisioning'])
const COLLATION: Intl.CollatorOptions = { sensitivity: 'base' }

const compareText = (left: string, right: string) => left.localeCompare(right, 'en', COLLATION)

function compareRows(left: VmRow, right: VmRow): number {
  return compareText(left.machineName, right.machineName) || compareText(left.name, right.name) || compareText(left.id, right.id)
}

/** Every VM (and container) of every machine, sorted by machine name, then VM name. Offline machines' VMs stay in, marked by their machine's state. */
export function vmRows(machines: Machine[]): VmRow[] {
  const rows = machines.flatMap((machine) =>
    machine.workloads.map((workload) => ({
      machineId: machine.id,
      machineName: machine.name,
      machineState: machine.state,
      machineOs: machine.os,
      id: workload.id,
      name: workload.name,
      kind: workload.kind,
      state: workload.state,
      cpu: workload.cpu,
      ramMb: workload.ram_mb,
      diskGb: workload.disk_gb,
      gpu: hasGpu(workload),
      note: reasonNote(readStoppedReason(workload.stopped_reason)),
      plain: isPlainMode(workload),
    })),
  )
  return rows.sort(compareRows)
}

/** The rows of one machine, or all of them when no machine is chosen. */
export const filterRows = (rows: VmRow[], machineId: string | null): VmRow[] => (machineId === null ? rows : rows.filter((row) => row.machineId === machineId))

/** The machine the address asks for, when it is a valid id of a machine on the list; otherwise null, which means all machines. */
export function vmFilterFromRoute(route: string, machines: Machine[]): string | null {
  const wanted = vmsMachineFromRoute(route)
  return machines.some((machine) => machine.id === wanted) ? wanted : null
}

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`

/** For example "12 VMs on 3 machines": the VMs shown and how many machines they are on. */
export function vmsHeader(rows: VmRow[]): string {
  if (rows.length === 0) return '0 VMs'
  const machines = new Set(rows.map((row) => row.machineId)).size
  return `${plural(rows.length, 'VM', 'VMs')} on ${plural(machines, 'machine', 'machines')}`
}

/** The state pill's colour for a VM state: green when running, amber while it changes, plain otherwise. */
export function vmTone(state: string): MachineState | '' {
  if (state === 'running') return 'online'
  return IN_PROGRESS.has(state) ? 'busy' : ''
}
