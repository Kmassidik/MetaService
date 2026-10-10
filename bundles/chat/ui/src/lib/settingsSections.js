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

export const SETTINGS_SECTIONS = Object.freeze([
  { id: SETTINGS.general, label: 'General', icon: 'settings' },
  { id: SETTINGS.computer, label: 'Computer', icon: 'computer' },
  { id: SETTINGS.apps, label: 'Connected apps', icon: 'apps' },
  { id: SETTINGS.notifications, label: 'Notifications', icon: 'bell' },
  { id: SETTINGS.usage, label: 'Usage & plan', icon: 'activity' },
  { id: SETTINGS.danger, label: 'Danger zone', icon: 'trash' },
])

export const DEFAULT_SETTINGS_SECTION = SETTINGS.general

export function isSettingsSection(id) {
  return SETTINGS_SECTIONS.some(section => section.id === id)
}

export function settingsSectionLabel(id) {
  return SETTINGS_SECTIONS.find(section => section.id === id)?.label || ''
}

/** A named section opens on itself (a phone too); a plain open starts at the list on a phone. */
export function openSettings(requested) {
  if (isSettingsSection(requested)) return { section: requested, listFirst: false }
  return { section: DEFAULT_SETTINGS_SECTION, listFirst: true }
}

/** Picking a section from the list pushes it; an unknown id leaves the panel as it was. */
export function showSettingsSection(state, id) {
  if (!isSettingsSection(id)) return state
  return { section: id, listFirst: false }
}

/** The phone's back arrow: the list again, remembering which section was open. */
export function backToSettingsList(state) {
  return { ...state, listFirst: true }
}
