// The panel's pages and the addresses that lead to them. Older addresses still work.
export type Page = 'overview' | 'machines' | 'vms' | 'usage' | 'health' | 'settings'

const PAGES: Record<string, Page> = {
  '/': 'overview',
  '/machines': 'machines',
  '/machines/find': 'machines',
  '/machines/details': 'machines',
  '/vms': 'vms',
  '/vms/create': 'vms',
  '/usage': 'usage',
  '/health': 'health',
  '/settings': 'settings',
  '/deployments': 'machines',
  '/scan': 'machines',
  '/activity': 'health',
  '/bundle': 'settings',
  '/ai': 'settings',
}

const MACHINE_ID = /^[a-z0-9][a-z0-9-]{0,62}$/
const split = (route: string) => {
  const [path = '', query = ''] = route.split('?')
  return { path, query: new URLSearchParams(query) }
}

/** The address of one machine's page, where its deployments and activity are. */
export const machineHref = (id: string) => `#/machines/details?id=${encodeURIComponent(id)}`

/** The machine a detail address (/machines/details?id=...) is about, or null for every other address. */
export function machineFromRoute(route: string): string | null {
  const { path, query } = split(route)
  const id = query.get('id') ?? ''
  return path === '/machines/details' && MACHINE_ID.test(id) ? id : null
}

const WORKLOAD_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/

/** The address of one VM's page: its machine's address plus the VM. */
export const vmHref = (machine: string, workload: string) => `${machineHref(machine)}&vm=${encodeURIComponent(workload)}`

/** The VM a detail address (/machines/details?id=<machine>&vm=<vm>) is about, or null when the address names no valid VM. */
export function vmFromRoute(route: string): string | null {
  if (machineFromRoute(route) === null) return null
  const vm = split(route).query.get('vm') ?? ''
  return WORKLOAD_ID.test(vm) ? vm : null
}

export type MachinesView = 'list' | 'find'
const MACHINES_VIEWS: Record<string, MachinesView> = { '/machines/find': 'find' }

/** Which screen the Machines page shows: the list of added machines, or Find machines. */
export const machinesView = (route: string): MachinesView => MACHINES_VIEWS[split(route).path] ?? 'list'

export type VmsView = 'list' | 'create'
const VMS_VIEWS: Record<string, VmsView> = { '/vms/create': 'create' }
const VMS_PATHS = new Set(['/vms', '/vms/create'])

/** Which screen the VMs page shows: every VM on every machine, or the form that makes a new one. */
export const vmsView = (route: string): VmsView => VMS_VIEWS[split(route).path] ?? 'list'

/** The machine kept in the address of a VMs page (?machine=<id>): the filter of All VMs, the preselected machine of Create VM. Null when absent or not a valid id. */
export function vmsMachineFromRoute(route: string): string | null {
  const { path, query } = split(route)
  if (!VMS_PATHS.has(path)) return null
  const id = query.get('machine') ?? ''
  return MACHINE_ID.test(id) ? id : null
}

const withMachine = (base: string, machine: string | null) => (machine ? `${base}?machine=${encodeURIComponent(machine)}` : base)

/** The address of All VMs, narrowed to one machine when given. */
export const vmsHref = (machine: string | null) => withMachine('#/vms', machine)

/** The address of Create VM, with a machine preselected when given. */
export const createVmHref = (machine: string | null) => withMachine('#/vms/create', machine)

export const pageFor = (route: string): Page => PAGES[split(route).path] ?? 'overview'
