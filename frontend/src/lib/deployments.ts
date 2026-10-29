// What a machine's Deployments tab needs, worked out from the machine the Root reports: its VMs as "servers" and the machine as the "host" of the building view.

import type { BuildingHost, BuildingServer } from './building.ts'
import { hasGpu } from './gpuChoice.ts'
import type { Machine, Workload } from './types.ts'

const PROGRESS = new Set(['creating', 'starting', 'provisioning', 'deleting'])

/** The VMs on one machine in the shape the building, cards and table all use. */
export function vmServers(machine: Machine): BuildingServer[] {
  return machine.workloads.map((workload) => ({
    id: workload.id,
    display: workload.name,
    status: workload.state,
    cls: workload.state === 'running' ? 'run' : PROGRESS.has(workload.state) ? 'prog' : '',
    mem_mb: workload.ram_mb,
    cpu: workload.cpu,
    disk_gb: workload.disk_gb,
    gpu: hasGpu(workload),
  }))
}

/** Apps stay a view of their managed VMs; no app or external service becomes another managed VM row. */
export function appWorkloads(machine: Machine): Workload[] {
  return machine.workloads.filter((workload) => workload.app != null)
}

/** The machine as the host of its VMs: how much memory, cores and disk it has and how much of the disk its VMs take. */
export function hostFor(machine: Machine): BuildingHost {
  return {
    chip: machine.name,
    apple: machine.os === 'macos' && machine.arch === 'arm64',
    ram_total_mb: machine.ram_total_mb ?? 0,
    ...(machine.settings?.ram_reserve_mb == null ? {} : { ram_reserve_mb: machine.settings.ram_reserve_mb }),
    cpu_total: machine.cpu_cores ?? 0,
    disk_total_gb: machine.disk_total_gb ?? 0,
    disk_free_gb: machine.free_disk_gb ?? null,
    disk_alloc_gb: machine.workloads.reduce((sum, workload) => sum + (workload.disk_gb ?? 0), 0),
  }
}
