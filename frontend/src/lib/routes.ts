// The panel's pages and the addresses that lead to them. Older addresses still work.
export type Page = 'overview' | 'machines' | 'usage' | 'health' | 'settings'

const PAGES: Record<string, Page> = {
  '/': 'overview',
  '/machines': 'machines',
  '/machines/find': 'machines',
  '/machines/details': 'machines',
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

export const pageFor = (route: string): Page => PAGES[split(route).path] ?? 'overview'
