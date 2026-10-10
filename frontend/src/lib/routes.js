// The panel's pages and the addresses that lead to them. Older addresses still work.
const PAGES = {
  '/': 'overview',
  '/machines': 'machines',
  '/machines/find': 'machines',
  '/deployments': 'deployments',
  '/usage': 'usage',
  '/health': 'health',
  '/settings': 'settings',
  '/scan': 'machines',
  '/activity': 'health',
  '/bundle': 'settings',
  '/ai': 'settings',
}

const MACHINE_DETAIL = /^\/deployments\/([a-z0-9][a-z0-9-]{0,62})$/

/** The machine a Deployments detail address is about, or null for every other address. */
export const machineFromRoute = (route) => MACHINE_DETAIL.exec(route)?.[1] ?? null

export const pageFor = (route) => (machineFromRoute(route) ? 'deployments' : (PAGES[route] ?? 'overview'))
