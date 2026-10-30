// The panel's pages and the addresses that lead to them. Older addresses still work.
import { tabFromName, type MachineTab } from './machineTabs.ts'

export type Page = 'overview' | 'machines' | 'vms' | 'usage' | 'health' | 'settings' | 'sandboxes' | 'share' | 'notfound'

const PAGES: Record<string, Page> = {
  '/': 'overview',
  '/machines': 'machines',
  '/machines/find': 'machines',
  '/machines/details': 'machines',
  '/vms': 'vms',
  '/vms/create': 'vms',
  '/usage': 'usage',
  '/sandboxes': 'sandboxes',
  '/keys': 'sandboxes',
  '/sandboxes/keys': 'sandboxes',
  '/sandboxes/usage': 'sandboxes',
  '/share': 'share',
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

/** The address of one machine's page, where its live numbers, VMs, settings and activity are. */
export const machineHref = (id: string) => `#/machines/details?id=${encodeURIComponent(id)}`

/** The address of one machine's Environment tab. */
export const environmentHref = (id: string) => `${machineHref(id)}&tab=environment`

/** The machine a detail address (/machines/details?id=...) is about, or null for every other address. */
export function machineFromRoute(route: string): string | null {
  const { path, query } = split(route)
  const id = query.get('id') ?? ''
  return path === '/machines/details' && MACHINE_ID.test(id) ? id : null
}

/** The tab a machine address names (?id=...&tab=...). Old names (overview, deployments) land on their new tab; no name opens Live. */
export const machineTabFromRoute = (route: string): MachineTab => tabFromName(split(route).query.get('tab'))

const WORKLOAD_ID =/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/

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

const CREATE_VM_PATH = '/vms/create'
const VMS_PATHS = new Set(['/vms', CREATE_VM_PATH])

/** True for the old Create VM address: All VMs is shown with the Create VM window open on top of it. */
export const createVmOpen = (route: string): boolean => split(route).path === CREATE_VM_PATH

/** The machine kept in the address of a VMs page (?machine=<id>): the filter of All VMs, the preselected machine of the Create VM window. Null when absent or not a valid id. */
export function vmsMachineFromRoute(route: string): string | null {
  const { path, query } = split(route)
  if (!VMS_PATHS.has(path)) return null
  const id = query.get('machine') ?? ''
  return MACHINE_ID.test(id) ? id : null
}

const withMachine = (base: string, machine: string | null) => (machine ? `${base}?machine=${encodeURIComponent(machine)}` : base)

/** The address of All VMs, narrowed to one machine when given. */
export const vmsHref = (machine: string | null) => withMachine('#/vms', machine)

/** The address that opens the Create VM window, with a machine preselected when given. */
export const createVmHref = (machine: string | null) => withMachine(`#${CREATE_VM_PATH}`, machine)

const TRAILING_SLASHES = /\/+$/

/** The path of an address without its trailing slashes, so /machines/ is /machines. The bare address stays "/". */
const normalisedPath = (route: string): string => split(route).path.replace(TRAILING_SLASHES, '') || '/'

/** The page an address leads to. An address the panel does not know leads to 'notfound'. */
export const pageFor = (route: string): Page => PAGES[normalisedPath(route)] ?? 'notfound'

const SHOWN_ADDRESS_MAX = 80

/** The text as the browser would show it, or as it is when it is not valid percent-encoding. */
function decoded(text: string): string {
  try {
    return decodeURIComponent(text)
  } catch {
    return text
  }
}

/** The address as the person typed it, for the Page not found screen: decoded when it can be, cut to a sensible length. Always shown as text. */
export function shownAddress(route: string): string {
  const typed = decoded(split(route).path)
  return typed.length > SHOWN_ADDRESS_MAX ? `${typed.slice(0, SHOWN_ADDRESS_MAX)}…` : typed
}
