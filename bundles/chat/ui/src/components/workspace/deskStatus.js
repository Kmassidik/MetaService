// Pure rules for what the computer panel shows. Kept apart from the Svelte files so they can be unit-tested.

// A tiny screenshot data URL is a blank page (for example X answering 403), not a useful screen.
const USEFUL_IMAGE_MIN_LENGTH = 14000
const BLOCKED_PATTERN = /blocked|HTTP 403/i
const STREAM_DOWN_STATES = new Set(['unavailable', 'error', 'failed'])
const STREAM_RECONNECT_STATES = new Set(['reconnecting', 'restarting'])
const NOVNC_PAGE = '/novnc/index.html'
// The computer's desktop without a bot: watching it never marks a bot as taken over (C21).
const ACCOUNT_DESKTOP_SOCKET = '/api/computer/desktop/ws'
// A computer whose status comes from the real desktop (C21 image) rather than a bot's browser.
const DESKTOP_MODE = 'desktop'

export const DeskPhase = Object.freeze({
  STARTING: 'starting',
  STREAM: 'stream',
  SNAPSHOT: 'snapshot',
  HOME: 'home',
})

export function isBlocked(message) {
  return BLOCKED_PATTERN.test(message || '')
}

export function isUsefulImage(image, message) {
  return Boolean(image) && image.length > USEFUL_IMAGE_MIN_LENGTH && !isBlocked(message)
}

export function isStreamMode(desktop) {
  return desktop?.mode === 'stream'
}

function streamPath(desktop) {
  if (!isStreamMode(desktop)) return ''
  return typeof desktop.wsPath === 'string' ? desktop.wsPath : ''
}

export function isStreamReady(desktop) {
  return Boolean(streamPath(desktop)) && !STREAM_DOWN_STATES.has(desktop?.state || '')
}

export function isStreamReconnecting(desktop) {
  return isStreamReady(desktop) && STREAM_RECONNECT_STATES.has(desktop.state)
}

function viewerSource(path, viewOnly) {
  return `${NOVNC_PAGE}?path=${encodeURIComponent(path)}${viewOnly ? '&view=1' : ''}`
}

export function streamSource(desktop) {
  if (!isStreamReady(desktop)) return ''
  return viewerSource(streamPath(desktop), false)
}

/** The side panel's live, watch-only picture of a computer that runs the real desktop. */
export function previewStreamSource(computer) {
  return computer?.mode === DESKTOP_MODE ? viewerSource(ACCOUNT_DESKTOP_SOCKET, true) : ''
}

// A stream-mode desktop without a socket path yet is still booting, so it reads as "starting".
function isStreamBooting(desktop) {
  return isStreamMode(desktop) && !streamPath(desktop) && !STREAM_DOWN_STATES.has(desktop?.state || '')
}

export function deskPhase({ desktop, image, message, busy }) {
  if (isStreamReady(desktop)) return DeskPhase.STREAM
  if (isUsefulImage(image, message)) return DeskPhase.SNAPSHOT
  if (busy || isStreamBooting(desktop)) return DeskPhase.STARTING
  return DeskPhase.HOME
}

export function homeHint({ message, image }) {
  if (isBlocked(message)) return 'This site blocked the bot’s browser. Open Chrome below and try google.com, or connect another way.'
  if (image) return 'The browser is open but the page is blank. Open Chrome on the dock.'
  return 'Open Chrome on the dock to browse.'
}

export function liveLabel(phase, updated) {
  if (phase === DeskPhase.STREAM) return 'Live'
  if (phase !== DeskPhase.SNAPSHOT) return ''
  return updated ? `Snapshot · ${updated}` : 'Snapshot'
}

export function canTakeOver(phase) {
  return phase === DeskPhase.STREAM || phase === DeskPhase.SNAPSHOT
}
