// What the Machines dropdown in the sidebar holds, and which item is the page being looked at.
import { machineFromRoute, machineHref, machinesView, pageFor } from './routes.ts'
import type { Machine } from './types.ts'

export interface MenuItem {
  key: string
  label: string
  href: string
  /** True for the page the person is on. */
  on: boolean
}

const LIST = '#/machines'
const FIND = '#/machines/find'

/** The machine list, each machine's own page, then Find machines. Only the page being looked at is marked. */
export function machinesMenu(route: string, machines: Pick<Machine, 'id' | 'name'>[]): MenuItem[] {
  const here = pageFor(route) === 'machines'
  const view = machinesView(route)
  const current = machineFromRoute(route)
  const own = machines.map((machine) => ({ key: machine.id, label: machine.name, href: machineHref(machine.id), on: here && current === machine.id }))
  return [
    { key: 'list', label: 'Machine list', href: LIST, on: here && view === 'list' && current === null },
    ...own,
    { key: 'find', label: 'Find machines', href: FIND, on: here && view === 'find' },
  ]
}
