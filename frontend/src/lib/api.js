// The only place that talks to the Root. Same-origin calls, cookie session, CSRF token kept in memory.

let csrfToken = null

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message)
    this.status = status
    this.code = code
  }
}

async function call(method, path, body, retried = false) {
  const headers = {}
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (method !== 'GET') headers['X-CSRF-Token'] = csrfToken ?? ''
  let response
  try {
    response = await fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'same-origin',
      cache: 'no-store',
    })
  } catch {
    throw new ApiError(0, 'unreachable', 'Cannot reach the Root.')
  }
  if (response.status === 204) return null
  const data = await response.json().catch(() => null)
  // The Root makes a new CSRF token each time it starts, so a panel left open across a restart asks for the new one and tries once more.
  if (response.status === 403 && method !== 'GET' && !retried && !path.startsWith('/api/auth/')) {
    await getSession()
    return call(method, path, body, true)
  }
  if (!response.ok) throw withNumbers(new ApiError(response.status, data?.error?.code ?? 'error', data?.error?.message ?? 'Request failed.'), data?.error)
  return data
}

const UNITS = { ram_mb: 'MB RAM', disk_gb: 'GB disk' }

function withNumbers(error, detail) {
  if (detail && Number.isInteger(detail.needed) && Number.isInteger(detail.free) && UNITS[detail.resource]) {
    error.numbers = { needed: detail.needed, free: detail.free, unit: UNITS[detail.resource] }
  }
  return error
}

/** The signed-in operator's name, or null when not signed in. Also stores the session's CSRF token. */
export async function getSession() {
  try {
    const session = await call('GET', '/api/session')
    csrfToken = session.csrf_token
    return session.username
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return null
    throw error
  }
}

export const authStatus = () => call('GET', '/api/auth/status')

/** First run: creates the admin login and signs in. */
export async function setupAdmin(username, password, confirm, setupToken) {
  const reply = await call('POST', '/api/auth/setup', { username, password, confirm, setup_token: setupToken })
  csrfToken = reply.csrf_token
  return reply.username
}

export async function login(username, password) {
  const reply = await call('POST', '/api/auth/login', { username, password })
  csrfToken = reply.csrf_token
  return reply.username
}

export const signOut = () => call('POST', '/api/auth/logout')

export const listMachines = async () => (await call('GET', '/api/machines')).machines
export const inviteMachine = (name) => call('POST', '/api/enrollments', { name })
export const removeMachine = (id) => call('DELETE', `/api/machines/${encodeURIComponent(id)}`)

export const scanSetup = () => call('GET', '/api/scan/setup')
export const startScan = () => call('POST', '/api/scans')
export const latestScan = async () => (await call('GET', '/api/scans/latest')).scan
export const addFromScan = (runId, items) => call('POST', `/api/scans/${runId}/add`, { items })

export const createWorkload = (body) => call('POST', '/api/workloads', body)
export const listCommands = async () => (await call('GET', '/api/commands?limit=15')).commands

export function workloadAction(machine, workload, action) {
  const body = action === 'delete' ? { confirm: true } : undefined
  return call('POST', `/api/machines/${encodeURIComponent(machine)}/workloads/${encodeURIComponent(workload)}/${action}`, body)
}

/** The numbers behind a refusal, when the Root gave them. */
export function refusalText(error) {
  return error.numbers ? `${error.message}: needs ${error.numbers.needed} ${error.numbers.unit}, the best machine has ${error.numbers.free} free.` : error.message
}

export const bundleOverview = () => call('GET', '/api/bundles')
export const pinBundle = (version) => call('POST', '/api/bundles/pin', { version })
export const rollbackBundle = () => call('POST', '/api/bundles/rollback')
export const installBundle = (machine, workload) =>
  call('POST', `/api/machines/${encodeURIComponent(machine)}/bundle/install`, workload ? { workload } : {})
export const chatLink = async (machine, workload) =>
  (await call('GET', `/api/chat-link?machine=${encodeURIComponent(machine)}${workload ? `&workload=${encodeURIComponent(workload)}` : ''}`)).url

export const brainStatus = () => call('GET', '/api/brain')
export const testBrain = () => call('POST', '/api/brain/test')
