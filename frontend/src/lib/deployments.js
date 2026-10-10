// What a machine's Deployments tab needs, worked out from the machine the Root reports: its VMs as "servers" and the machine as the "host" of the building view.

const PROGRESS = new Set(['creating', 'starting', 'provisioning'])

/** The VMs on one machine in the shape the building, cards and table all use. */
export function vmServers(machine) {
  return machine.workloads.map((workload) => ({
    id: workload.id,
    display: workload.name,
    status: workload.state,
    cls: workload.state === 'running' ? 'run' : PROGRESS.has(workload.state) ? 'prog' : '',
    mem_mb: workload.ram_mb,
    cpu: workload.cpu,
    disk_gb: workload.disk_gb,
  }))
}

/** The machine as the host of its VMs: how much memory, cores and disk it has and how much of the disk its VMs take. */
export function hostFor(machine) {
  return {
    chip: machine.name,
    apple: machine.os === 'macos' && machine.arch === 'arm64',
    ram_total_mb: machine.ram_total_mb ?? 0,
    ram_reserve_mb: machine.settings?.ram_reserve_mb ?? undefined,
    cpu_total: machine.cpu_cores ?? 0,
    disk_total_gb: machine.disk_total_gb ?? 0,
    disk_free_gb: machine.free_disk_gb ?? null,
    disk_alloc_gb: machine.workloads.reduce((sum, workload) => sum + (workload.disk_gb ?? 0), 0),
  }
}
