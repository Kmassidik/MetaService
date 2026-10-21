// What the VM page shows, worked out from a machine and one of its VMs. The page copies the MAAS detail page, so the names here follow its tabs and rows.
import { bundleFlag, formatGb, formatMb } from './format.ts'
import { vmServers } from './deployments.ts'
import type { BuildingServer } from './building.ts'
import type { Machine, Workload } from './types.ts'

export type VmTab = 'overview' | 'monitoring' | 'access' | 'danger'

export const VM_TABS: VmTab[] = ['overview', 'monitoring', 'access', 'danger']

export const STOPPED_STATE = 'stopped'
export const RUNNING_STATE = 'running'

/** The tab names as MAAS writes them: first letter big. */
export const tabLabel = (tab: VmTab): string => tab[0]?.toUpperCase() + tab.slice(1)

export function findWorkload(machine: Machine, workloadId: string): Workload | undefined {
  return machine.workloads.find((workload) => workload.id === workloadId)
}

/** The VM in the shape the MAAS view uses (display name, status, status colour). */
export function findServer(machine: Machine, workloadId: string): BuildingServer | undefined {
  return vmServers(machine).find((server) => server.id === workloadId)
}

/** Which button the header shows: Start for a stopped VM, Stop for a running one, none while it is being made. */
export function headerAction(state: string): 'start' | 'stop' | null {
  if (state === STOPPED_STATE) return 'start'
  return state === RUNNING_STATE ? 'stop' : null
}

/** "2 vCPU · 4 GB · 40 GB", as the Specs row of MAAS. */
export const specsText = (workload: Workload): string => `${workload.cpu} vCPU · ${formatMb(workload.ram_mb)} · ${formatGb(workload.disk_gb)}`

export interface VmFact {
  label: string
  /** null where the page shows the status tag. */
  value: string | null
}

/** The rows of the Overview tab (MAAS: ID, Status, Bundle, Runtime, Specs, SSH domain). The SSH domain row has no MetaService data, so Address and Machine take its place. */
export function vmFacts(machine: Machine, workload: Workload, pinned: string | null | undefined): VmFact[] {
  return [
    { label: 'ID', value: workload.id },
    { label: 'Status', value: null },
    { label: 'Ruvio', value: bundleFlag(workload.bundle_version, pinned).text.replace(/^no chat$/, 'not installed') },
    { label: 'Runtime', value: workload.kind },
    { label: 'Specs', value: specsText(workload) },
    { label: 'Address', value: workload.address ?? '— none yet —' },
    { label: 'Machine', value: machine.name },
  ]
}

/** What the Monitoring tab says. MetaService has no live numbers for a VM yet, so it only says why there are none. */
export const monitoringMessage = (state: string): string => (state === STOPPED_STATE ? '● stopped — no live metrics' : 'no live metrics reported yet')
