// What the All VMs page shows: every VM of every machine as one row, narrowed to one machine, sorted, with a count. Pure functions, no DOM, no network.
import { appChip, type AppChip } from './appInstall.ts'
import { readGpuMemoryGb } from './gpuBooking.ts'
import { hasGpu } from './gpuChoice.ts'
import { vmsMachineFromRoute } from './routes.ts'
import { isPlainMode, readStoppedReason, reasonNote, type StopNote } from './stoppedReason.ts'
import type { Machine, MachineState, Workload, WorkloadKind } from './types.ts'

export interface VmRow {
  machineId: string
  machineName: string
  machineState: MachineState
  id: string
  name: string
  kind: WorkloadKind
  state: string
  cpu: number
  ramMb: number
  diskGb: number
  /** True when it was given the machine's GPU. */
  gpu: boolean
  /** The GPU memory limit booked for it, in GB; null when it has none. */
  gpuLimitGb: number | null
  /** Why it stopped, when it stopped by itself and the machine said why. */
  note: StopNote | null
  /** True when it runs without systemd. */
  plain: boolean
  /** The chip for the app being installed in the VM; null when it has none. */
  app: AppChip | null
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
      id: workload.id,
      name: workload.name,
      kind: workload.kind,
      state: workload.state,
      cpu: workload.cpu,
      ramMb: workload.ram_mb,
      diskGb: workload.disk_gb,
      gpu: hasGpu(workload),
      gpuLimitGb: readGpuMemoryGb(workload.gpu_memory_gb),
      note: reasonNote(readStoppedReason(workload.stopped_reason)),
      plain: isPlainMode(workload),
      app: appChip(workload.app),
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

/** The machine and the VM a row was made from, so its buttons can act on them. Null only when the machines changed since the row was made. */
export function findVm(machines: Machine[], row: Pick<VmRow, 'machineId' | 'id'>): { machine: Machine; workload: Workload } | null {
  const machine = machines.find((entry) => entry.id === row.machineId)
  const workload = machine?.workloads.find((entry) => entry.id === row.id)
  return machine && workload ? { machine, workload } : null
}
