// The panel's pages and the addresses that lead to them. Older addresses still work.
const PAGES = {
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
const split = (route) => {
  const [path, query = ''] = route.split('?')
  return { path, query: new URLSearchParams(query) }
}

/** The address of one machine's page, where its deployments and activity are. */
export const machineHref = (id) => `#/machines/details?id=${encodeURIComponent(id)}`

/** The machine a detail address (/machines/details?id=...) is about, or null for every other address. */
export function machineFromRoute(route) {
  const { path, query } = split(route)
  const id = query.get('id') ?? ''
  return path === '/machines/details' && MACHINE_ID.test(id) ? id : null
}

export const pageFor = (route) => PAGES[split(route).path] ?? 'overview'
