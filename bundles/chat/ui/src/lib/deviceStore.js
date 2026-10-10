/**
 * Per-device preferences in localStorage. Private windows, blocked site data and some
 * embedded previews throw on access, so every read falls back and every write reports
 * whether it stuck instead of breaking the page.
 */

export function readDevice(key, storage = globalThis.localStorage) {
  try {
    return storage?.getItem(key) ?? null
  } catch {
    return null // unavailable storage reads as "never saved"
  }
}

export function writeDevice(key, value, storage = globalThis.localStorage) {
  try {
    storage.setItem(key, value)
    return true
  } catch {
    return false // the caller tells the person it applies to this visit only
  }
}
