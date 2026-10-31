// What the dropdowns in the sidebar (Machines, Settings) hold, and which item is the page being looked at.
import { machinesView, pageFor } from './routes.ts'

export interface MenuItem {
  key: string
  label: string
  href: string
  /** True for the page the person is on. */
  on: boolean
}

/** The machine list, Find machines and Share a PC (a computer somewhere else joins the machines). A machine's own page belongs to the list, so the list stays marked there. Nothing is marked on other pages of the panel. */
export function machinesMenu(route: string): MenuItem[] {
  const here = pageFor(route) === 'machines'
  const view = machinesView(route)
  return [
    { key: 'list', label: 'Machine list', href: '#/machines', on: here && view === 'list' },
    { key: 'find', label: 'Find machines', href: '#/machines/find', on: here && view === 'find' },
    { key: 'share', label: 'Share a PC', href: '#/share', on: pageFor(route) === 'share' },
  ]
}

/** Settings and AI access (MCP): the settings of the panel itself, and who may use it through an AI client. */
export function settingsMenu(route: string): MenuItem[] {
  const page = pageFor(route)
  return [
    { key: 'general', label: 'General', href: '#/settings', on: page === 'settings' },
    { key: 'mcp', label: 'AI access (MCP)', href: '#/mcp', on: page === 'mcp' },
  ]
}
