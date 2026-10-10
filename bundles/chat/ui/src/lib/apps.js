// Pure rules for Connect apps on the computer's browser (one login per account, shared by every
// bot). An app is Connected only when the server's login check (probe) says logged_in.

export const LoginState = Object.freeze({
  LOGGED_IN: 'logged_in',
  LOGGED_OUT: 'logged_out',
  UNKNOWN: 'unknown',
})

export const AppState = Object.freeze({
  CONNECTED: 'connected',
  CHECKING: 'checking',
  NEEDS_CHECK: 'needs-check',
  NOT_CONNECTED: 'not-connected',
})

const KNOWN_STATES = new Set(Object.values(LoginState))
const READY_COMPUTER = 'ready'

const LABELS = {
  [AppState.CONNECTED]: 'Connected',
  [AppState.CHECKING]: 'Checking…',
  [AppState.NEEDS_CHECK]: 'Not signed in',
  [AppState.NOT_CONNECTED]: '',
}

export function appRecord(apps = [], appId) {
  return apps.find(app => app.appId === appId) || null
}

export function loginStateOf(record) {
  const raw = record?.loginState
  return KNOWN_STATES.has(raw) ? raw : LoginState.UNKNOWN
}

export function isConnected(record) {
  return loginStateOf(record) === LoginState.LOGGED_IN
}

/** What one app's card or row shows; `checkingId` is the app whose login is being checked. */
export function appState(record, appId, checkingId = '') {
  if (checkingId && checkingId === appId) return AppState.CHECKING
  if (!record) return AppState.NOT_CONNECTED
  return isConnected(record) ? AppState.CONNECTED : AppState.NEEDS_CHECK
}

export function appStateLabel(state, record = null) {
  if (state === AppState.NEEDS_CHECK && !record?.checkedAt) return 'Not checked yet'
  return LABELS[state] ?? ''
}

/** The account's apps that can be connected now (`isOffered`: the catalog's isConnectable). */
export function offeredApps(apps = [], isOffered = () => true) {
  return apps.filter(app => isOffered(app.appId))
}

/**
 * Apps to check again when Connect apps (or Settings › Connected apps) opens: every offered app
 * not signed in at its last check, since the owner may have finished signing in after it. Only
 * on a running computer: a check never wakes or sets one up.
 */
export function appsToRecheck(apps = [], environment = null, isOffered = () => true) {
  if (environment?.state !== READY_COMPUTER) return []
  return offeredApps(apps, isOffered).filter(app => !isConnected(app)).map(app => app.appId)
}

// While the owner signs in on the computer, the login is checked on its own: first after
// CONNECT_POLL_FIRST_MS, then each wait CONNECT_POLL_BACKOFF times longer (at most
// CONNECT_POLL_MAX_MS), until the sign-in shows up or CONNECT_POLL_LIMIT_MS have passed.
export const CONNECT_POLL_FIRST_MS = 3000
export const CONNECT_POLL_BACKOFF = 1.5
export const CONNECT_POLL_MAX_MS = 15000
export const CONNECT_POLL_LIMIT_MS = 600000 // ten minutes

// The server answers 409 while another computer action runs (one at a time per account, e.g. the
// screen preview) or while the computer is not running. An automatic check then simply waits for
// its next turn: the app keeps its last answer, and nothing is wrong to show.
const COMPUTER_BUSY = 409

/** True for a failed automatic check that should just be tried again later. */
export function checkCanWait(error) {
  return error?.status === COMPUTER_BUSY
}

/** How long to wait before the `attempt`-th automatic check (0 = the first). */
export function connectPollDelay(attempt) {
  return Math.min(CONNECT_POLL_FIRST_MS * CONNECT_POLL_BACKOFF ** attempt, CONNECT_POLL_MAX_MS)
}

/** Whether to keep checking: the flow is still open, not signed in yet, and within the limit. */
export function keepPolling({ open, connected, elapsedMs }) {
  return open && !connected && elapsedMs < CONNECT_POLL_LIMIT_MS
}

// A bot run that used the browser may have signed in or out of an app; the apps are checked again
// once, this long after the last such run finished (several runs in a row cost one check).
export const RECHECK_AFTER_RUN_MS = 10000
const BROWSER_TOOLS = new Set(['browser', 'ruvio_desktop', 'ruvio_message_person', 'ruvio_search_email', 'ruvio_send_email',
  'ruvio_reply_email', 'ruvio_find_free_time', 'ruvio_schedule_event', 'ruvio_move_event', 'ruvio_cancel_event', 'ruvio_post'])
const RUNTIME_EVENT = 'runtime'
const TOOL_EVENT = 'tool'

/** Apps to check after a browser run: every offered app on record, signed in or not (a bot may
 * have signed out too). Only on a running computer. */
export function appsAfterRun(apps = [], environment = null, isOffered = () => true) {
  if (environment?.state !== READY_COMPUTER) return []
  return offeredApps(apps, isOffered).map(app => app.appId)
}

/** True when a run's public events show a browser or screen tool call. */
export function runUsedBrowser(events = []) {
  return events.some(event => event?.kind === RUNTIME_EVENT
    && event.payload?.type === TOOL_EVENT
    && BROWSER_TOOLS.has(event.payload?.name))
}

/** Signed-in apps, newest first, with a display name; for the sidebar pill and Settings. */
export function connectedAppList(apps = [], nameOf = id => id) {
  return apps.filter(isConnected).map(app => ({ id: app.appId, name: nameOf(app.appId) }))
}

/** The message after a check that did not find a login. */
export function notSignedInMessage(name, record) {
  if (loginStateOf(record) === LoginState.LOGGED_OUT) return `${name} isn’t signed in yet. Finish signing in on the computer, then tap I’m signed in.`
  return `Ruvio couldn’t confirm the ${name} sign-in yet. Finish signing in on the computer, then tap I’m signed in again.`
}
