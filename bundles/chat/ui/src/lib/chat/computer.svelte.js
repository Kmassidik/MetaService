import { tick, untrack } from 'svelte'
import { fail, bytes } from '../format.js'
import { api } from './client.svelte.js'
import { updateEnvironment, clearComputerWorkspace } from './environment.svelte.js'
import { loadAgents } from './agents.svelte.js'
import { chat, fileSession, computerVersions } from './state.svelte.js'
import { isOwnerBusy, keptDesktop, nextDesktop } from './desktopState.js'
import { isStreamMode } from '../../components/workspace/deskStatus.js'

export { updateEnvironment, clearComputerWorkspace }

/** The owner's computer used without a bot (Connect apps). Keyed like a bot in the computer maps. */
export const ACCOUNT_COMPUTER = 'computer'
/** How often the open big view polls its computer. */
const DESKTOP_POLL_MS = 3000
/** The big view's focus target; LiveComputer renders it. */
export const COMPUTER_VIEW_ID = 'workspace-computer'

/** The computer the panel shows: the account's while an app is being connected, else the bot's. */
export function deskKey() {
  return chat.connectingApp ? ACCOUNT_COMPUTER : chat.selectedId
}

function computerPath(id) {
  return id === ACCOUNT_COMPUTER ? '/api/computer' : `/api/agents/${encodeURIComponent(id)}/computer`
}

function desktopPath(id) {
  return id === ACCOUNT_COMPUTER ? '/api/computer/desktop' : `/api/agents/${encodeURIComponent(id)}/desktop`
}

/** Opens the computer big: over the chat area on desktop, full screen on phone. */
export async function openComputer() {
  chat.showComputer = true
  await tick()
  document.getElementById(COMPUTER_VIEW_ID)?.focus()
}

export function openTeachSheet() {
  chat.teachOpen = true
  return openComputer()
}

/**
 * Closing the big view must clear server takeover. GET …/desktop always records one
 * (`openAgentDesktop`); the UI often never sees `computers[id].state === 'takeover'` while
 * streaming, so gating release on that left chat blocked ("Tap I'm done…"). Always try
 * release — idle computers accept it cleanly.
 */
function shouldReleaseOnClose(id) {
  return Boolean(id) && !chat.computerBusy[id] && !chat.pending
}

export async function closeComputer() {
  chat.showComputer = false
  const id = deskKey()
  if (shouldReleaseOnClose(id)) await computerAction('release')
  chat.connectingApp = null
  chat.connectProbeError = ''
}

export function environmentBusy() {
  return Boolean(
    chat.deletingAccount
    || chat.environmentAction
    || chat.environmentLoading
    || chat.pending
    || chat.uploads.length
    || chat.agents.some(agent => ['running', 'provisioning'].includes(agent.status))
    || Object.values(chat.computerBusy).some(Boolean),
  )
}

export function environmentTransitioning() {
  return ['provisioning', 'deleting'].includes(chat.environment?.state)
}

export async function loadEnvironment() {
  if (chat.environmentLoading || chat.environmentAction || chat.deletingAccount) return
  const version = ++chat.environmentVersion
  chat.environmentLoading = true
  try {
    const data = await api('/api/environment')
    if (!chat.alive || !chat.session || version !== chat.environmentVersion) return
    chat.environmentRefreshError = ''
    if (updateEnvironment(data.environment)) await loadAgents()
  } catch (error) {
    if (chat.alive && chat.session && version === chat.environmentVersion) chat.environmentRefreshError = fail(error)
  } finally {
    if (chat.alive) chat.environmentLoading = false
  }
}

export async function manageEnvironment(action) {
  if (!chat.environment || environmentBusy() || environmentTransitioning() || chat.loggingOut) return
  if (action === 'delete' && (!chat.confirmEnvironmentDeletion || chat.environmentConfirmation !== 'DELETE')) return
  chat.environmentAction = action
  chat.environmentVersion += 1
  chat.agentsVersion += 1
  clearTimeout(chat.provisioningPoll)
  chat.environmentError = ''
  chat.environmentNotice = ''
  try {
    const data = await api('/api/environment', action === 'delete'
      ? { method: 'DELETE' }
      : { method: 'POST', body: JSON.stringify({ action }) })
    if (!chat.alive || !chat.session) return
    if (action === 'delete') {
      chat.confirmEnvironmentDeletion = false
      chat.environmentConfirmation = ''
      if (data.ok) {
        clearComputerWorkspace()
        updateEnvironment(null)
        chat.environmentNotice = 'Your private computer, bots, and conversation histories have been deleted.'
      } else {
        updateEnvironment(data.environment)
        chat.environmentNotice = 'Deletion is queued. We’ll keep checking until your private computer and its data are removed.'
      }
    } else {
      updateEnvironment(data.environment)
      chat.environmentNotice = action === 'wake' ? 'Your private computer is awake.' : 'Your private computer is suspended. Its saved files and bots are kept.'
    }
  } catch (error) {
    if (chat.alive && chat.session) chat.environmentError = fail(error)
  } finally {
    if (chat.alive) {
      chat.environmentAction = ''
      if (chat.session) await loadAgents()
    }
  }
}

export async function requestComputer(id, action, fields = {}, signal) {
  const key = chat.session?.csrf
  const version = (computerVersions.get(id) || 0) + 1
  computerVersions.set(id, version)
  const data = await api(computerPath(id), action === 'status'
    ? { signal }
    : { method: 'POST', body: JSON.stringify({ action, ...fields }), signal })
  if (!fileSession(key) || signal?.aborted || computerVersions.get(id) !== version) return
  chat.computers = { ...chat.computers, [id]: data }
  chat.computerUpdated = { ...chat.computerUpdated, [id]: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) }
  chat.computerErrors = { ...chat.computerErrors, [id]: '' }
  return data
}

function setDesktop(id, desktop) {
  chat.desktops = { ...chat.desktops, [id]: desktop }
}

/**
 * Polls the desktop stream (GET …/desktop also starts the desktop when it is down). A failed poll
 * keeps the last known desktop: the owner busy for a moment (409) or a host without the desktop
 * yet is not a reason to drop a live stream to a snapshot (bug-log #37).
 */
async function pollDesktop(id, signal) {
  const key = chat.session?.csrf
  try {
    const data = await api(desktopPath(id), { signal })
    if (fileSession(key) && !signal.aborted) setDesktop(id, nextDesktop(chat.desktops[id], data))
  } catch {
    if (fileSession(key) && !signal.aborted) setDesktop(id, keptDesktop(chat.desktops[id]))
  }
}

function showComputerError(id, error, signal) {
  if (signal.aborted || !chat.alive || !chat.session || isOwnerBusy(error)) return
  chat.computerErrors = { ...chat.computerErrors, [id]: fail(error) }
}

// Without a stream, the view shows the browser: its status first, then fresh screenshots.
async function pollBrowser(id, first, signal) {
  try {
    await requestComputer(id, first ? 'status' : 'screenshot', {}, signal)
  } catch (error) {
    showComputerError(id, error, signal)
  }
}

/** One poll of the big view. Exported for its unit test. */
export async function refreshComputerView(id, { first = false, signal }) {
  if (chat.computerBusy[id]) return
  await pollDesktop(id, signal)
  if (!isStreamMode(chat.desktops[id])) return pollBrowser(id, first, signal)
  if (chat.alive && chat.session) chat.computerErrors = { ...chat.computerErrors, [id]: '' }
}

export async function computerAction(action, fields = {}) {
  const id = deskKey()
  if (!id || chat.computerBusy[id] || chat.pending) return
  if (action === 'type' && (!fields.text || bytes(fields.text) > 2000)) {
    chat.computerErrors = { ...chat.computerErrors, [id]: 'Text must be 2000 UTF-8 bytes or fewer.' }
    return
  }
  chat.computerErrors = { ...chat.computerErrors, [id]: '' }
  chat.computerBusy = { ...chat.computerBusy, [id]: true }
  try {
    if (action === 'open') {
      const url = new URL(chat.computerUrl)
      if (!['https:', 'http:'].includes(url.protocol)) throw new Error('Use a complete http:// or https:// address.')
      fields = { url: url.href }
    }
    await requestComputer(id, action, fields)
    if (action === 'type' && deskKey() === id) chat.computerText = ''
  } catch (error) {
    if (chat.alive && chat.session) chat.computerErrors = { ...chat.computerErrors, [id]: fail(error) }
  } finally {
    if (chat.alive) chat.computerBusy = { ...chat.computerBusy, [id]: false }
  }
}

export function clickComputer(event) {
  const computer = chat.computers[deskKey()] || {}
  if (computer.state !== 'takeover' || chat.computerBusy[deskKey()]) return
  const image = event.currentTarget.querySelector('img')
  if (!image?.naturalWidth || !image.naturalHeight) return
  const box = image.getBoundingClientRect()
  const x = Math.max(0, Math.min(image.naturalWidth - 1, Math.floor((event.clientX - box.left) * image.naturalWidth / box.width)))
  const y = Math.max(0, Math.min(image.naturalHeight - 1, Math.floor((event.clientY - box.top) * image.naturalHeight / box.height)))
  computerAction('click', { x, y })
}

/** Must run during App component init (not at module import). */
export function installComputerEffects() {
  $effect(() => {
    if (chat.modal !== 'account' || !chat.session || chat.deletingAccount) return
    let cancelled = false
    let timer
    async function refresh() {
      await loadEnvironment()
      if (!cancelled) timer = setTimeout(refresh, 3000)
    }
    untrack(refresh)
    return () => { cancelled = true; clearTimeout(timer) }
  })

  $effect(() => {
    const id = deskKey()
    const enabled = chat.showComputer && chat.session && id && chat.modal !== 'account' && !chat.environmentAction && !['suspended', 'deleting'].includes(chat.environment?.state)
    if (!enabled) return
    const controller = new AbortController()
    let timer
    async function refresh(first = false) {
      await refreshComputerView(id, { first, signal: controller.signal })
      if (!controller.signal.aborted) timer = setTimeout(() => refresh(false), DESKTOP_POLL_MS)
    }
    untrack(() => refresh(true))
    return () => { controller.abort(); clearTimeout(timer) }
  })
}

