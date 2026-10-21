// What the dropdown in the sidebar (Machines) holds, and which item is the page being looked at.
import { machinesView, pageFor } from './routes.ts'

export interface MenuItem {
  key: string
  label: string
  href: string
  /** True for the page the person is on. */
  on: boolean
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
