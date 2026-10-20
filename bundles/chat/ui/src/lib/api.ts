import { isRecord } from './check.ts'
import { ApiError } from './errors.ts'

/** What the server sent, not yet checked: callers pass it through a `parse…` function. */
export type Api = (path: string, options?: RequestInit) => Promise<unknown>

/** Request options with the signal set only when there is one (an absent signal is not `undefined`). */
export const withSignal = (init: RequestInit, signal?: AbortSignal): RequestInit => (signal ? { ...init, signal } : init)

interface ApiConfig {
  getCsrf: () => string | undefined
  onUnauthorized: () => void
  requests: Set<AbortController>
}

const UNAUTHORIZED = 401

function failureMessage(data: unknown, status: number): string {
  if (isRecord(data) && typeof data.error === 'string' && data.error) return data.error
  return `Request failed (${status}). Please try again.`
}

/** Create a same-origin JSON API client bound to session + unauthorized reset. */
export function createApi({ getCsrf, onUnauthorized, requests }: ApiConfig): Api {
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
      const data: unknown = await response.json().catch(() => null)
      if (response.status === UNAUTHORIZED && getCsrf() === requestSession) onUnauthorized()
      if (!response.ok) throw new ApiError(failureMessage(data, response.status), response.status)
      if (!data) throw new Error('The server returned an unreadable response. Please try again.')
      return data
    } finally {
      requests.delete(controller)
      options.signal?.removeEventListener('abort', abort)
    }
  }
}
