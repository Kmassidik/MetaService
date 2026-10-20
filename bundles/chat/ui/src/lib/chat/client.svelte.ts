import { type Api, createApi } from '../api.ts'
import { chat, requests } from './state.svelte.ts'

/** Late-bound so session can register onUnauthorized after files are loadable. */
export const apiHooks = {
  onUnauthorized(): void {},
}

export const api: Api = createApi({
  getCsrf: () => chat.session?.csrf,
  onUnauthorized: () => apiHooks.onUnauthorized(),
  requests,
})
