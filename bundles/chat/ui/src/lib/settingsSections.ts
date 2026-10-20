/**
 * Settings sections and the panel's navigation state, kept pure so it can be tested.
 * Desktop shows the list and a section side by side; a phone shows one at a time, so the
 * state also says whether the list comes first (`listFirst`).
 */

export const SETTINGS = Object.freeze({
  general: 'general',
  computer: 'computer',
  apps: 'apps',
  notifications: 'notifications',
  usage: 'usage',
  danger: 'danger',
})

export type SettingsSectionId = (typeof SETTINGS)[keyof typeof SETTINGS]

export interface SettingsSection {
  id: SettingsSectionId
  label: string
  icon: string
}

/** Which section is open, and (phones) whether the list shows first. */
export interface SettingsState {
  section: SettingsSectionId
  listFirst: boolean
}

export const SETTINGS_SECTIONS: readonly SettingsSection[] = Object.freeze([
  { id: SETTINGS.general, label: 'General', icon: 'settings' },
  { id: SETTINGS.computer, label: 'Computer', icon: 'computer' },
  { id: SETTINGS.apps, label: 'Connected apps', icon: 'apps' },
  { id: SETTINGS.notifications, label: 'Notifications', icon: 'bell' },
  { id: SETTINGS.usage, label: 'Usage & plan', icon: 'activity' },
  { id: SETTINGS.danger, label: 'Danger zone', icon: 'trash' },
])

export const DEFAULT_SETTINGS_SECTION: SettingsSectionId = SETTINGS.general

export function isSettingsSection(id: unknown): id is SettingsSectionId {
  return SETTINGS_SECTIONS.some(section => section.id === id)
}

export function settingsSectionLabel(id: string): string {
  return SETTINGS_SECTIONS.find(section => section.id === id)?.label || ''
}

/** A named section opens on itself (a phone too); a plain open starts at the list on a phone. */
export function openSettings(requested?: string | null): SettingsState {
  if (isSettingsSection(requested)) return { section: requested, listFirst: false }
  return { section: DEFAULT_SETTINGS_SECTION, listFirst: true }
}

/** Picking a section from the list pushes it; an unknown id leaves the panel as it was. */
export function showSettingsSection(state: SettingsState, id: string): SettingsState {
  if (!isSettingsSection(id)) return state
  return { section: id, listFirst: false }
}

/** The phone's back arrow: the list again, remembering which section was open. */
export function backToSettingsList(state: SettingsState): SettingsState {
  return { ...state, listFirst: true }
}
