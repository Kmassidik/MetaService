/**
 * The right-hand side panel (P6): open/close (remembered per device), its tab, the profile it
 * shows, and the view-only computer preview on its Computer tab.
 */
import { tick, untrack } from 'svelte'
import { DRAWER_MAX_WIDTH, MODALS } from '../constants.js'
import { fail } from '../format.js'
import { PANEL_TABS, readPanelOpen, resolveTab, savePanelOpen } from '../sidePanel.js'
import { chat, selectedAgent } from './state.svelte.js'
import { loadProfile } from './profile.svelte.js'
import { requestComputer } from './computer.svelte.js'
import { guardUnsaved } from './unsavedGuard.svelte.js'

export const SIDE_PANEL_ID = 'side-panel'
// Status checks are passive: they neither wake the computer nor keep it awake.
const PREVIEW_POLL_MS = 3000
const STATUS_ACTION = 'status'
const READY_STATE = 'ready'
// On a phone the panel covers the chat, so a remembered "open" would hide the chat on every visit.
const PHONE_QUERY = `(max-width: ${DRAWER_MAX_WIDTH}px)`

function setPanelOpen(open) {
  chat.sidePanelOpen = open
  savePanelOpen(open)
}

async function showSidePanel(tab) {
  chat.sidePanelTab = resolveTab(tab, selectedAgent())
  setPanelOpen(true)
  await tick()
  document.getElementById(SIDE_PANEL_ID)?.focus()
}

function hideSidePanel() {
  setPanelOpen(false)
  chat.profileError = ''
  chat.profileHighlight = {}
}

// Changing the shown tab leaves Details, so unsaved edits there are asked about first.
export function openSidePanel(tab = chat.sidePanelTab) {
  if (resolveTab(tab, selectedAgent()) === chat.sidePanelTab) return showSidePanel(tab)
  return guardUnsaved(() => showSidePanel(tab))
}

export function closeSidePanel() {
  return guardUnsaved(hideSidePanel)
}

export function toggleSidePanel() {
  if (chat.sidePanelOpen) return closeSidePanel()
  return openSidePanel()
}

export function selectPanelTab(tab) {
  guardUnsaved(() => { chat.sidePanelTab = resolveTab(tab, selectedAgent()) })
}

export const openProfile = () => openSidePanel(PANEL_TABS.details)
export const openFiles = () => openSidePanel(PANEL_TABS.files)

/** True while the owner can see the bot's Details, so profile changes flash there instead of in chat. */
export function profileVisible() {
  return chat.sidePanelOpen && chat.sidePanelTab === PANEL_TABS.details
}

/** Reopens the panel on a computer where it was left open. */
export function restoreSidePanel() {
  if (window.matchMedia(PHONE_QUERY).matches) return
  chat.sidePanelOpen = readPanelOpen()
}

// The bot whose screen the Computer tab previews, or '' when the preview should not ask.
function previewTarget() {
  const active = selectedAgent()
  if (!chat.sidePanelOpen || !chat.session || !active) return ''
  if (resolveTab(chat.sidePanelTab, active) !== PANEL_TABS.computer) return ''
  // The big view polls the same computer itself; an asleep or absent computer has no screen to ask.
  if (chat.showComputer || chat.modal === MODALS.account || chat.environment?.state !== READY_STATE) return ''
  return active.id
}

async function refreshPreview(id, signal) {
  if (chat.computerBusy[id]) return
  try {
    await requestComputer(id, STATUS_ACTION, {}, signal)
  } catch (error) {
    if (!signal.aborted) chat.computerErrors = { ...chat.computerErrors, [id]: fail(error) }
  }
}

function pollPreview(id) {
  const controller = new AbortController()
  let timer
  async function refresh() {
    await refreshPreview(id, controller.signal)
    if (!controller.signal.aborted) timer = setTimeout(refresh, PREVIEW_POLL_MS)
  }
  untrack(refresh)
  return () => { controller.abort(); clearTimeout(timer) }
}

/** Must run during App component init (not at module import). */
export function installSidePanelEffects() {
  $effect(() => {
    if (!chat.sidePanelOpen || !chat.selectedId) return
    untrack(loadProfile)
  })

  $effect(() => {
    const id = previewTarget()
    if (!id) return
    return pollPreview(id)
  })
}
