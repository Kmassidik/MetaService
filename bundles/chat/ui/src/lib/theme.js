/**
 * Light / Dark / System. The choice is saved on this device and turned into `data-theme` on
 * <html>; System leaves the attribute off so style.css follows `prefers-color-scheme`.
 * index.html repeats the read before first paint (no white flash); keep THEME_STORAGE_KEY in sync.
 */
import { readDevice, writeDevice } from './deviceStore.js'

export const THEME_STORAGE_KEY = 'ruvio-theme'
export const THEMES = Object.freeze({ system: 'system', light: 'light', dark: 'dark' })
export const THEME_OPTIONS = Object.freeze([
  { id: THEMES.system, label: 'System' },
  { id: THEMES.light, label: 'Light' },
  { id: THEMES.dark, label: 'Dark' },
])
export const DEFAULT_THEME = THEMES.system

export function normalizeTheme(value) {
  return Object.values(THEMES).includes(value) ? value : DEFAULT_THEME
}

/** The `data-theme` value for a choice; null (no attribute) means follow the system. */
export function themeAttribute(choice) {
  const theme = normalizeTheme(choice)
  return theme === THEMES.system ? null : theme
}

/** What actually shows: System resolves through the device's dark-mode setting. */
export function resolveTheme(choice, prefersDark) {
  return themeAttribute(choice) || (prefersDark ? THEMES.dark : THEMES.light)
}

export function readTheme(storage) {
  return normalizeTheme(readDevice(THEME_STORAGE_KEY, storage))
}

export function applyTheme(choice, root = document.documentElement) {
  const attribute = themeAttribute(choice)
  if (attribute) root.dataset.theme = attribute
  else delete root.dataset.theme
}

/** Applies at once and saves; false means it could not be saved (lasts for this visit only). */
export function chooseTheme(choice, storage) {
  const theme = normalizeTheme(choice)
  applyTheme(theme)
  return writeDevice(THEME_STORAGE_KEY, theme, storage)
}
