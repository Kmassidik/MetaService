// The only place that talks to the Root. Same-origin calls, cookie session, CSRF token kept in memory.

let csrfToken = null

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message)
    this.status = status
    this.code = code
  }
}

async function call(method, path, body) {
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
  if (!response.ok) throw new ApiError(response.status, data?.error?.code ?? 'error', data?.error?.message ?? 'Request failed.')
  return data
}

/** The signed-in operator, or null when not signed in. Also stores the CSRF token. */
export async function getSession() {
  try {
    const session = await call('GET', '/api/session')
    csrfToken = session.csrf_token
    return { email: session.email }
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return null
    throw error
  }
}

export const authStatus = () => call('GET', '/auth/status')
export const listMachines = async () => (await call('GET', '/api/machines')).machines
export const inviteMachine = (name) => call('POST', '/api/enrollments', { name })
export const removeMachine = (id) => call('DELETE', `/api/machines/${encodeURIComponent(id)}`)
export const signOut = () => call('POST', '/auth/logout')
