/**
 * Pure rules for the right-hand side panel (P6): which tabs a conversation has, whether the panel
 * opens by itself on this device, and the one line under the computer preview.
 */
import { type DeviceStorage, readDevice, writeDevice } from './deviceStore.ts'
import type { Agent } from './types.ts'

export const PANEL_OPEN_KEY = 'ruvio-side-panel'
const STORED_OPEN = 'open'
const STORED_CLOSED = 'closed'

export const PANEL_TABS = Object.freeze({ details: 'details', files: 'files', computer: 'computer' })
export type PanelTab = (typeof PANEL_TABS)[keyof typeof PANEL_TABS]
export interface PanelTabItem {
  id: PanelTab
  label: string
}
type ChatKind = Pick<Agent, 'kind'>

const BOT_TABS: readonly PanelTabItem[] = Object.freeze([
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
export type PreviewTone = (typeof PREVIEW_TONE)[keyof typeof PREVIEW_TONE]
export interface PreviewLine {
  text: string
  tone: PreviewTone
  wake: boolean
}
const ENVIRONMENT_LINES: Readonly<Record<string, PreviewLine>> = Object.freeze({
  provisioning: { text: 'Setting up…', tone: PREVIEW_TONE.busy, wake: false },
  suspended: { text: 'Asleep · tap to wake', tone: PREVIEW_TONE.asleep, wake: true },
  deleting: { text: 'Being deleted', tone: PREVIEW_TONE.idle, wake: false },
  failed: { text: 'Needs attention', tone: PREVIEW_TONE.idle, wake: false },
})
const NOT_SET_UP: PreviewLine = { text: 'Not set up yet', tone: PREVIEW_TONE.idle, wake: false }
const IN_CONTROL: PreviewLine = { text: 'You have control', tone: PREVIEW_TONE.control, wake: false }
const IDLE: PreviewLine = { text: 'Idle', tone: PREVIEW_TONE.idle, wake: false }
// Until the remote desktop (C21) the bots only drive their browser, so the app is always Chrome.
const BROWSER_APP = 'Chrome'

export function panelTabs(active: ChatKind | null | undefined): readonly PanelTabItem[] {
  if (!active) return NO_CHAT_TABS
  return active.kind === TEAM_KIND ? GROUP_TABS : BOT_TABS
}

/** The tab to show: the one asked for when this conversation has it, else its first (Details for a chat). */
export function resolveTab(tab: string, active: ChatKind | null | undefined): PanelTab {
  const tabs = panelTabs(active)
  return tabs.find(item => item.id === tab)?.id ?? tabs[0]?.id ?? PANEL_TABS.details
}

/** The panel shows for a chat, or for Files alone when it was asked for with no chat selected. */
export function isPanelShown({ open, active, tab }: { open: boolean, active: ChatKind | null | undefined, tab: string }): boolean {
  return open && (Boolean(active) || tab === PANEL_TABS.files)
}

/** Whether the panel was left open on this device (closed when never saved or unreadable). */
export function readPanelOpen(storage?: DeviceStorage): boolean {
  return readDevice(PANEL_OPEN_KEY, storage) === STORED_OPEN
}

export function savePanelOpen(open: boolean, storage?: DeviceStorage): boolean {
  return writeDevice(PANEL_OPEN_KEY, open ? STORED_OPEN : STORED_CLOSED, storage)
}

interface PreviewState {
  botName: string
  environmentState?: string | undefined
  takingOver: boolean
  runActive: boolean
}

/**
 * The line under the preview: the computer's own state first (setting up, asleep), then who is
 * using it. `wake` marks the line as a tap target that wakes the computer.
 */
export function previewStatus({ botName, environmentState, takingOver, runActive }: PreviewState): PreviewLine {
  if (!environmentState) return NOT_SET_UP
  const environmentLine = ENVIRONMENT_LINES[environmentState]
  if (environmentLine) return environmentLine
  if (takingOver) return IN_CONTROL
  if (runActive) return { text: `${botName} is using ${BROWSER_APP}`, tone: PREVIEW_TONE.busy, wake: false }
  return IDLE
}
