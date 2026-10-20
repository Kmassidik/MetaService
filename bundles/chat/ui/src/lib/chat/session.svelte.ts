import { untrack } from 'svelte'
import { parseConfig, parseOnboarding, parseSession } from '../answers/account.ts'
import { isBoolean, isString, objectOf } from '../check.ts'
import { errorMessage, errorStatus } from '../errors.ts'
import { fail } from '../format.ts'
import { api, apiHooks } from './client.svelte.ts'
import { resetFiles, cancelUpload, loadFiles } from './files.svelte.ts'
import { loadAgents } from './agents.svelte.ts'
import { loadApps } from './apps.svelte.ts'
import { loadUsage, loadStorage, loadStorageGate } from './usage.svelte.ts'
import { chat, requireSession, waitlisted } from './state.svelte.ts'

export { loadUsage, loadStorage, loadStorageGate }

const isDeletionAnswer = objectOf<{ ok: boolean, status: string }>({ ok: isBoolean, status: isString })
const CONFLICT = 409
const UNAUTHORIZED = 401

export function onUnauthorized(): void {
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

export async function initialize(): Promise<void> {
  const authError = new URLSearchParams(window.location.search).get('authError')
  chat.bootError = authError === 'configuration'
    ? 'Google sign-in is unavailable because of a server configuration problem. Please contact the administrator.'
    : authError === 'capacity' ? 'Ruvio is at capacity. New registrations are temporarily paused. Existing users can still sign in.'
    : authError === 'deleting' ? 'That account is still being removed. Wait a minute, then try Google sign-in again.'
    : authError !== null ? 'Google sign-in did not finish. Close other Ruvio tabs and try Continue with Google again.' : ''
  try {
    const session = parseSession(await api('/api/me'))
    chat.session = session
    chat.onboarding = session.onboarding || null
    chat.environment = session.environment || null
    if (chat.onboarding && !waitlisted()) await Promise.all([loadAgents(), loadUsage(), loadFiles(), loadStorageGate(), loadApps()])
  } catch (error) {
    if (chat.alive && errorStatus(error) !== UNAUTHORIZED) chat.bootError = fail(error)
  } finally {
    if (chat.alive && !chat.session) {
      try { const config = parseConfig(await api('/api/config')); chat.googleConfigured = config.googleConfigured; chat.registrationCapacity = config.capacity }
      catch (error) { if (chat.alive) chat.bootError = fail(error) }
    }
    if (chat.alive) chat.booting = false
  }
}

export async function saveOnboarding(event: Event): Promise<void> {
  event.preventDefault()
  if (chat.onboardingSaving || !chat.onboardingGoal || !chat.onboardingSource) return
  if (chat.onboardingGoal === 'other' && !chat.onboardingGoalDetail.trim()) { chat.onboardingError = 'Tell us what you want your agents to help with.'; return }
  if (chat.onboardingSource === 'other' && !chat.onboardingSourceDetail.trim()) { chat.onboardingError = 'Tell us where you heard about Ruvio.'; return }
  chat.onboardingSaving = true; chat.onboardingError = ''
  try {
    const onboarding = parseOnboarding(await api('/api/onboarding', { method: 'POST', body: JSON.stringify({
      goal: chat.onboardingGoal, goalDetail: chat.onboardingGoalDetail.trim(), source: chat.onboardingSource, sourceDetail: chat.onboardingSourceDetail.trim(),
    }) }))
    chat.onboarding = onboarding
    chat.session = { ...requireSession(), onboarding }
    if (!waitlisted()) await Promise.all([loadAgents(), loadUsage(), loadFiles(), loadStorageGate(), loadApps()])
  } catch (error) { if (chat.alive) chat.onboardingError = fail(error) }
  finally { if (chat.alive) chat.onboardingSaving = false }
}

export async function redeemInvite(event: Event): Promise<void> {
  event.preventDefault()
  if (chat.inviteSaving || !chat.inviteCode.trim()) return
  chat.inviteSaving = true; chat.inviteError = ''
  try {
    await api('/api/access/redeem', { method: 'POST', body: JSON.stringify({ code: chat.inviteCode.trim() }) })
    const session = requireSession()
    chat.session = { ...session, user: { ...session.user, access: 'active' } }
    chat.inviteCode = ''
    await Promise.all([loadAgents(), loadUsage(), loadFiles(), loadStorageGate(), loadApps()])
  } catch (error) { if (chat.alive) chat.inviteError = fail(error) }
  finally { if (chat.alive) chat.inviteSaving = false }
}

export async function deleteAccount(event: Event): Promise<void> {
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
    if (!isDeletionAnswer(data) || data.ok !== true || data.status !== 'deleting') throw new Error('The server did not confirm account deletion. Your account may still be active; check before trying again.')
    resetFiles()
    chat.session = null
    window.location.assign('/')
  } catch (error) {
    if (chat.alive) {
      chat.accountDeletionError = deletionFailureMessage(error)
    }
  } finally {
    if (chat.alive) chat.deletingAccount = false
  }
}

const COMPUTER_HOLD = /Computer|Give back|I’m done|takeover|browser control/i

/** What the owner reads when account deletion did not go through. */
function deletionFailureMessage(error: unknown): string {
  const raw = errorMessage(error)
  const status = errorStatus(error)
  if (status === CONFLICT && COMPUTER_HOLD.test(raw)) return 'Finish in Computer first — open it and tap Give back — then delete your account.'
  if (status === CONFLICT) return raw || 'Could not start deletion. Try again in a moment.'
  if (status) return raw
  return 'We could not confirm whether account deletion started. Check your account before trying again.'
}

export async function logout(): Promise<void> {
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
export function installSessionEffects(): void {
  $effect(() => {
    if (!chat.session?.csrf || !chat.onboarding) return
    let cancelled = false
    let timer: ReturnType<typeof setTimeout> | undefined
    async function refreshGate() {
      await loadStorageGate()
      if (!cancelled) timer = setTimeout(refreshGate, 60000)
    }
    untrack(refreshGate)
    return () => { cancelled = true; clearTimeout(timer) }
  })
}
