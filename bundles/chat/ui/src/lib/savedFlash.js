/**
 * A brief "Saved" tick per control: `show(key)` turns it on, and it turns itself off after
 * SAVED_FLASH_MS. Showing the same key again restarts its timer.
 */

export const SAVED_FLASH_MS = 2000

/** `onChange(key, shown)` receives every on/off; the owner keeps the state. */
export function createSavedFlash(onChange, duration = SAVED_FLASH_MS) {
  const timers = new Map()

  function hide(key) {
    clearTimeout(timers.get(key))
    timers.delete(key)
    onChange(key, false)
  }

  function show(key) {
    clearTimeout(timers.get(key))
    onChange(key, true)
    timers.set(key, setTimeout(() => hide(key), duration))
  }

  return { show, hide }
}
