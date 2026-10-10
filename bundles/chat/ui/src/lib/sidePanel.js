/**
 * Pure rules for the right-hand side panel (P6): which tabs a conversation has, whether the panel
 * opens by itself on this device, and the one line under the computer preview.
 */
import { readDevice, writeDevice } from './deviceStore.js'

export const PANEL_OPEN_KEY = 'ruvio-side-panel'
const STORED_OPEN = 'open'
const STORED_CLOSED = 'closed'

export const PANEL_TABS = Object.freeze({ details: 'details', files: 'files', computer: 'computer' })
const BOT_TABS = Object.freeze([
  { id: PANEL_TABS.details, label: 'Details' },
  { id: PANEL_TABS.files, label: 'Files' },
  { id: PANEL_TABS.computer, label: 'Computer' },
])
// A group has no computer of its own: its members' work shows on their own panels.
const GROUP_TABS = Object.freeze(BOT_TABS.filter(tab => tab.id !== PANEL_TABS.computer))
// Saved files belong to the account, so Files still opens (from Settings or Help) with no chat selected.
const NO_CHAT_TABS = Object.freeze(BOT_TABS.filter(tab => tab.id === PANEL_TABS.files))
const TEAM_KIND = 'team'

export const PREVIEW_TONE = Object.freeze({ busy: 'busy', idle: 'idle', asleep: 'asleep', control: 'control' })
const ENVIRONMENT_LINES = Object.freeze({
  provisioning: { text: 'Setting up…', tone: PREVIEW_TONE.busy, wake: false },
  suspended: { text: 'Asleep · tap to wake', tone: PREVIEW_TONE.asleep, wake: true },
  deleting: { text: 'Being deleted', tone: PREVIEW_TONE.idle, wake: false },
  failed: { text: 'Needs attention', tone: PREVIEW_TONE.idle, wake: false },
})
const NOT_SET_UP = { text: 'Not set up yet', tone: PREVIEW_TONE.idle, wake: false }
const IN_CONTROL = { text: 'You have control', tone: PREVIEW_TONE.control, wake: false }
const IDLE = { text: 'Idle', tone: PREVIEW_TONE.idle, wake: false }
// Until the remote desktop (C21) the bots only drive their browser, so the app is always Chrome.
const BROWSER_APP = 'Chrome'

export function panelTabs(active) {
  if (!active) return NO_CHAT_TABS
  return active.kind === TEAM_KIND ? GROUP_TABS : BOT_TABS
}

/** The tab to show: the one asked for when this conversation has it, else its first (Details for a chat). */
export function resolveTab(tab, active) {
  const tabs = panelTabs(active)
  return tabs.some(item => item.id === tab) ? tab : tabs[0].id
}

/** The panel shows for a chat, or for Files alone when it was asked for with no chat selected. */
export function isPanelShown({ open, active, tab }) {
  return open && (Boolean(active) || tab === PANEL_TABS.files)
}

/** Whether the panel was left open on this device (closed when never saved or unreadable). */
export function readPanelOpen(storage) {
  return readDevice(PANEL_OPEN_KEY, storage) === STORED_OPEN
}

export function savePanelOpen(open, storage) {
  return writeDevice(PANEL_OPEN_KEY, open ? STORED_OPEN : STORED_CLOSED, storage)
}

/**
 * The line under the preview: the computer's own state first (setting up, asleep), then who is
 * using it. `wake` marks the line as a tap target that wakes the computer.
 * @param {{ botName: string, environmentState?: string, takingOver: boolean, runActive: boolean }} state
 */
export function previewStatus({ botName, environmentState, takingOver, runActive }) {
  if (!environmentState) return NOT_SET_UP
  const environmentLine = ENVIRONMENT_LINES[environmentState]
  if (environmentLine) return environmentLine
  if (takingOver) return IN_CONTROL
  if (runActive) return { text: `${botName} is using ${BROWSER_APP}`, tone: PREVIEW_TONE.busy, wake: false }
  return IDLE
}
