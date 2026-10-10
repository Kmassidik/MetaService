/** Create a same-origin JSON API client bound to session + unauthorized reset. */
export function createApi({ getCsrf, onUnauthorized, requests }) {
  return async function api(path, options = {}) {
    const requestSession = getCsrf()
    const controller = new AbortController()
    requests.add(controller)
    const abort = () => controller.abort()
    if (options.signal?.aborted) controller.abort()
    else options.signal?.addEventListener('abort', abort, { once: true })
    try {
      const headers = new Headers(options.headers)
      if (!headers.has('Accept')) headers.set('Accept', 'application/json')
      if (options.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json')
      if (options.method && options.method !== 'GET') headers.set('X-CSRF-Token', requestSession || '')
      const response = await fetch(path, {
        ...options,
        credentials: 'same-origin',
        signal: controller.signal,
        headers,
      })
      const data = await response.json().catch(() => null)
      if (response.status === 401 && getCsrf() === requestSession) onUnauthorized()
      if (!response.ok) {
        const error = new Error(data?.error || `Request failed (${response.status}). Please try again.`)
        error.status = response.status
        throw error
      }
      if (!data) throw new Error('The server returned an unreadable response. Please try again.')
      return data
    } finally {
      requests.delete(controller)
      options.signal?.removeEventListener('abort', abort)
    }
  }
}
