import { fail } from '../format.js'
import { api } from './client.svelte.js'
import { chat } from './state.svelte.js'

export async function loadUsage() {
  if (chat.deletingAccount) return
  chat.usageError = ''
  try { chat.usage = await api('/api/usage') }
  catch (error) { if (chat.alive) chat.usageError = fail(error) }
}

/**
 * Cheap create-gate (host capacity only). No guest SSH.
 * Use for sign-in, polling, and before New bot / group create.
 */
export async function loadStorageGate() {
  if (!chat.session || chat.storageLoading || chat.deletingAccount) return
  const key = chat.session.csrf
  chat.storageLoading = true
  try {
    const gate = await api('/api/storage/gate')
    if (!chat.alive || chat.session?.csrf !== key) return
    const previous = chat.storage || {}
    chat.storage = {
      ...previous,
      host: gate.host,
      limits: gate.limits,
      canCreateAgent: gate.canCreateAgent,
      creationBlockedReason: gate.creationBlockedReason,
    }
    if (gate.canCreateAgent) delete chat.storage.creationBlockedReason
    chat.storageError = ''
  } catch (error) {
    if (chat.alive && chat.session?.csrf === key) { chat.storage = null; chat.storageError = fail(error) }
  } finally { chat.storageLoading = false }
}

/**
 * Full storage (host + Results + guest computer). Settings / Refresh only.
 */
export async function loadStorage() {
  if (!chat.session || chat.storageLoading || chat.deletingAccount) return
  const key = chat.session.csrf
  chat.storageLoading = true
  try {
    const value = await api('/api/storage')
    if (!chat.alive || chat.session?.csrf !== key) return
    chat.storage = value
    chat.storageError = ''
  } catch (error) {
    if (chat.alive && chat.session?.csrf === key) { chat.storage = null; chat.storageError = fail(error) }
  } finally { chat.storageLoading = false }
}
