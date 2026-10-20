/**
 * Per-device preferences in localStorage. Private windows, blocked site data and some
 * embedded previews throw on access, so every read falls back and every write reports
 * whether it stuck instead of breaking the page.
 */

/** The two calls the preferences need; a test passes a plain object with them. */
export type DeviceStorage = Pick<Storage, 'getItem' | 'setItem'>

export function readDevice(key: string, storage: DeviceStorage | undefined = globalThis.localStorage): string | null {
  try {
    return storage?.getItem(key) ?? null
  } catch {
    return null // unavailable storage reads as "never saved"
  }
}

export function writeDevice(key: string, value: string, storage: DeviceStorage | undefined = globalThis.localStorage): boolean {
  try {
    if (!storage) return false
    storage.setItem(key, value)
    return true
  } catch {
    return false // the caller tells the person it applies to this visit only
  }
}
