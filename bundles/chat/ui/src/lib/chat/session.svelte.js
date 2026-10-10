import { untrack } from 'svelte'
import { fail } from '../format.js'
import { api, apiHooks } from './client.svelte.js'
import { resetFiles, cancelUpload, loadFiles } from './files.svelte.js'
import { loadAgents } from './agents.svelte.js'
import { loadApps } from './apps.svelte.js'
import { loadUsage, loadStorage, loadStorageGate } from './usage.svelte.js'
import { chat, waitlisted } from './state.svelte.js'

export { loadUsage, loadStorage, loadStorageGate }

export function onUnauthorized() {
  resetFiles()
  chat.session = null
  chat.agents = []
  chat.histories = {}
  chat.drafts = {}
  chat.pending = null
  chat.computers = {}
  chat.desktops = {}
  chat.connectProbeError = ''
  chat.loading = {}
  chat.showComputer = false
  chat.selectedId = ''
  chat.environment = null
  chat.environmentVersion += 1
  chat.agentsVersion += 1
  clearTimeout(chat.provisioningPoll)
  chat.dialog?.close()
  chat.modal = null
}

apiHooks.onUnauthorized = onUnauthorized

export async function initialize() {
  const authError = new URLSearchParams(window.location.search).get('authError')
  chat.bootError = authError === 'configuration'
    ? 'Google sign-in is unavailable because of a server configuration problem. Please contact the administrator.'
    : authError === 'capacity' ? 'Ruvio is at capacity. New registrations are temporarily paused. Existing users can still sign in.'
    : authError === 'deleting' ? 'That account is still being removed. Wait a minute, then try Google sign-in again.'
    : authError !== null ? 'Google sign-in did not finish. Close other Ruvio tabs and try Continue with Google again.' : ''
  try {
    chat.session = await api('/api/me')
    chat.onboarding = chat.session.onboarding || null
    chat.environment = chat.session.environment || null
    if (chat.onboarding && !waitlisted()) await Promise.all([loadAgents(), loadUsage(), loadFiles(), loadStorageGate(), loadApps()])
  } catch (error) {
    if (chat.alive && error.status !== 401) chat.bootError = fail(error)
  } finally {
    if (chat.alive && !chat.session) {
      try { const config = await api('/api/config'); chat.googleConfigured = config.googleConfigured; chat.registrationCapacity = config.capacity }
      catch (error) { if (chat.alive) chat.bootError = fail(error) }
    }
    if (chat.alive) chat.booting = false
  }
}

export async function saveOnboarding(event) {
  event.preventDefault()
  if (chat.onboardingSaving || !chat.onboardingGoal || !chat.onboardingSource) return
  if (chat.onboardingGoal === 'other' && !chat.onboardingGoalDetail.trim()) { chat.onboardingError = 'Tell us what you want your agents to help with.'; return }
  if (chat.onboardingSource === 'other' && !chat.onboardingSourceDetail.trim()) { chat.onboardingError = 'Tell us where you heard about Ruvio.'; return }
  chat.onboardingSaving = true; chat.onboardingError = ''
  try {
    const data = await api('/api/onboarding', { method: 'POST', body: JSON.stringify({
      goal: chat.onboardingGoal, goalDetail: chat.onboardingGoalDetail.trim(), source: chat.onboardingSource, sourceDetail: chat.onboardingSourceDetail.trim(),
    }) })
    chat.onboarding = data.onboarding
    chat.session = { ...chat.session, onboarding: chat.onboarding }
    if (!waitlisted()) await Promise.all([loadAgents(), loadUsage(), loadFiles(), loadStorageGate(), loadApps()])
  } catch (error) { if (chat.alive) chat.onboardingError = fail(error) }
  finally { if (chat.alive) chat.onboardingSaving = false }
}

export async function redeemInvite(event) {
  event.preventDefault()
  if (chat.inviteSaving || !chat.inviteCode.trim()) return
  chat.inviteSaving = true; chat.inviteError = ''
  try {
    await api('/api/access/redeem', { method: 'POST', body: JSON.stringify({ code: chat.inviteCode.trim() }) })
    chat.session = { ...chat.session, user: { ...chat.session.user, access: 'active' } }
    chat.inviteCode = ''
    await Promise.all([loadAgents(), loadUsage(), loadFiles(), loadStorageGate(), loadApps()])
  } catch (error) { if (chat.alive) chat.inviteError = fail(error) }
  finally { if (chat.alive) chat.inviteSaving = false }
}

export async function deleteAccount(event) {
  event.preventDefault()
  if (!chat.session || chat.deletingAccount || chat.loggingOut || chat.environmentAction || !chat.confirmAccountDeletion) return
  chat.accountDeletionError = ''
  if (chat.accountConfirmation !== 'DELETE') {
    chat.accountDeletionError = 'Type DELETE exactly to confirm account deletion.'
    return
  }
  chat.deletingAccount = true
  try {
    const data = await api('/api/account', { method: 'DELETE', body: JSON.stringify({ confirmation: chat.accountConfirmation }) })
    if (data.ok !== true || data.status !== 'deleting') throw new Error('The server did not confirm account deletion. Your account may still be active; check before trying again.')
    resetFiles()
    chat.session = null
    window.location.assign('/')
  } catch (error) {
    if (chat.alive) {
      const raw = String(error.message || '')
      if (error.status === 409 && /Computer|Give back|I’m done|takeover|browser control/i.test(raw)) {
        chat.accountDeletionError = 'Finish in Computer first — open it and tap Give back — then delete your account.'
      } else if (error.status === 409) {
        chat.accountDeletionError = raw || 'Could not start deletion. Try again in a moment.'
      } else if (error.status) {
        chat.accountDeletionError = raw
      } else {
        chat.accountDeletionError = 'We could not confirm whether account deletion started. Check your account before trying again.'
      }
    }
  } finally {
    if (chat.alive) chat.deletingAccount = false
  }
}

export async function logout() {
  if (chat.loggingOut || chat.pending || chat.environmentAction || chat.deletingAccount) return
  chat.loggingOut = true
  chat.formError = ''
  await Promise.all(chat.uploads.map(cancelUpload))
  if (chat.uploads.some(upload => upload.status === 'Cleanup failed')) {
    chat.formError = 'Some chat.uploads could not be deleted. Remove them in the chat.composer or Results before signing out.'
    chat.loggingOut = false
    return
  }
  chat.showComputer = false
  try {
    await api('/auth/logout', { method: 'POST' })
    resetFiles()
    chat.session = null
    window.location.assign('/')
  } catch (error) { if (chat.alive) chat.formError = fail(error) }
  finally { if (chat.alive) chat.loggingOut = false }
}

/** Must run during App component init (not at module import). */
export function installSessionEffects() {
  $effect(() => {
    if (!chat.session?.csrf || !chat.onboarding) return
    let cancelled = false
    let timer
    async function refreshGate() {
      await loadStorageGate()
      if (!cancelled) timer = setTimeout(refreshGate, 60000)
    }
    untrack(refreshGate)
    return () => { cancelled = true; clearTimeout(timer) }
  })
}
