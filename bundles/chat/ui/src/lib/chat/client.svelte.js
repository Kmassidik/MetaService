import { createApi } from '../api.js'
import { chat, requests } from './state.svelte.js'

/** Late-bound so session can register onUnauthorized after files are loadable. */
export const apiHooks = {
  onUnauthorized() {},
}

export const api = createApi({
  getCsrf: () => chat.session?.csrf,
  onUnauthorized: () => apiHooks.onUnauthorized(),
  requests,
})
