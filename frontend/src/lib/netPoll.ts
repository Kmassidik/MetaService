// Asks for a panel's numbers every `intervalMs` while the browser tab is visible, the same way the Live tab does. `load` gets a check that says whether its run is still the one in charge.
import { browserEnvironment, startPolling } from './statsPoll.ts'

/** Starts the asking; the returned function stops it for good, and any answer still on its way is thrown away. */
export function pollWhileVisible(intervalMs: number, load: (current: () => boolean) => Promise<void>): () => void {
  let running = true
  const stop = startPolling(browserEnvironment(), intervalMs, () => load(() => running))
  return () => {
    running = false
    stop()
  }
}
