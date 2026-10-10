// What the big view knows about a computer's desktop stream, merged poll by poll. Pure, so it is
// unit-tested apart from the Svelte state.

const OWNER_BUSY = 409
const KNOWN_MODES = new Set(['stream', 'browser'])

/** No desktop known yet: the view falls back to the browser's screenshots. */
export const NO_DESKTOP = Object.freeze({ state: 'unavailable', mode: 'browser', wsPath: '', message: '' })

function desktopOf(data) {
  return data.desktop && typeof data.desktop === 'object' ? data.desktop : data
}

function socketPath(desktop, known) {
  return typeof desktop.wsPath === 'string' && desktop.wsPath ? desktop.wsPath : known.wsPath
}

/**
 * The desktop after a successful poll. A reply without a socket path (a raw desktop_ensure result)
 * keeps the path already known, so a working stream is never torn down by it (bug-log #37).
 */
export function nextDesktop(previous, data) {
  const known = previous || NO_DESKTOP
  if (!data || typeof data !== 'object') return known
  const desktop = desktopOf(data)
  return {
    state: desktop.state || known.state,
    mode: KNOWN_MODES.has(desktop.mode) ? desktop.mode : known.mode,
    wsPath: socketPath(desktop, known),
    message: desktop.message || '',
  }
}

/**
 * The desktop after a failed poll: the owner was busy (409) or this host has no desktop yet. The
 * last known desktop stays, so one busy poll never drops a live stream to a snapshot (bug-log #37).
 */
export function keptDesktop(previous) {
  return previous || NO_DESKTOP
}

/** Another computer call held the owner for a moment; the next poll simply tries again. */
export function isOwnerBusy(error) {
  return error?.status === OWNER_BUSY
}
