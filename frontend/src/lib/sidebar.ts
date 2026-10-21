// What the dropdowns in the sidebar (Machines, VMs) hold, and which item is the page being looked at.
import { createVmHref, machinesView, pageFor, vmsHref, vmsView } from './routes.ts'

export interface MenuItem {
  key: string
  label: string
  href: string
  /** True for the page the person is on. */
  on: boolean
}

/** All VMs and Create VM, with no machine names in it. Nothing is marked on other pages of the panel. */
export function vmsMenu(route: string): MenuItem[] {
  const here = pageFor(route) === 'vms'
  const view = vmsView(route)
  return [
    { key: 'all', label: 'All VMs', href: vmsHref(null), on: here && view === 'list' },
    { key: 'create', label: 'Create VM', href: createVmHref(null), on: here && view === 'create' },
  ]
}

/** The machine list and Find machines. A machine's own page belongs to the list, so the list stays marked there. Nothing is marked on other pages of the panel. */
export function machinesMenu(route: string): MenuItem[] {
  const here = pageFor(route) === 'machines'
  const view = machinesView(route)
  return [
    { key: 'list', label: 'Machine list', href: '#/machines', on: here && view === 'list' },
    { key: 'find', label: 'Find machines', href: '#/machines/find', on: here && view === 'find' },
  ]
}
