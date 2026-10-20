import { parseStorage, parseStorageGate, parseUsage } from '../answers/account.ts'
import type { AccountStorage } from '../types.ts'
import { fail } from '../format.ts'
import { api } from './client.svelte.ts'
import { chat } from './state.svelte.ts'

export async function loadUsage(): Promise<void> {
  if (chat.deletingAccount) return
  chat.usageError = ''
  try { chat.usage = parseUsage(await api('/api/usage')) }
  catch (error) { if (chat.alive) chat.usageError = fail(error) }
}

/** The gate's answer laid over what is already known (the meters stay until Refresh). */
function mergeGate(known: AccountStorage | null, gate: AccountStorage): AccountStorage {
  const merged: AccountStorage = { ...known, host: gate.host, limits: gate.limits, canCreateAgent: gate.canCreateAgent }
  if (gate.canCreateAgent || gate.creationBlockedReason === undefined) delete merged.creationBlockedReason
  else merged.creationBlockedReason = gate.creationBlockedReason
  return merged
}

/**
 * Cheap create-gate (host capacity only). No guest SSH.
 * Use for sign-in, polling, and before New bot / group create.
 */
export async function loadStorageGate(): Promise<void> {
  if (!chat.session || chat.storageLoading || chat.deletingAccount) return
  const key = chat.session.csrf
  chat.storageLoading = true
  try {
    const gate = parseStorageGate(await api('/api/storage/gate'))
    if (!chat.alive || chat.session?.csrf !== key) return
    chat.storage = mergeGate(chat.storage, gate)
    chat.storageError = ''
  } catch (error) {
    if (chat.alive && chat.session?.csrf === key) { chat.storage = null; chat.storageError = fail(error) }
  } finally { chat.storageLoading = false }
}

/**
 * Full storage (host + Results + guest computer). Settings / Refresh only.
 */
export async function loadStorage(): Promise<void> {
  if (!chat.session || chat.storageLoading || chat.deletingAccount) return
  const key = chat.session.csrf
  chat.storageLoading = true
  try {
    const value = parseStorage(await api('/api/storage'))
    if (!chat.alive || chat.session?.csrf !== key) return
    chat.storage = value
    chat.storageError = ''
  } catch (error) {
    if (chat.alive && chat.session?.csrf === key) { chat.storage = null; chat.storageError = fail(error) }
  } finally { chat.storageLoading = false }
}
